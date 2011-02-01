#!/usr/bin/env ruby

require File.expand_path('../graphviz', __FILE__)
require File.expand_path('../d_source_parser_types', __FILE__)

module DSourceParser

# TODO: Create map to replace "alised" types.
# TODO: extern(C) int method(..)
# TODO: union
# TODO: Block: private {...}
# TODO: Add parameters to draw.
# TODO: import lib1, lib2,...;
# TODO: import lib1 : func1;

# Gets index of close-char take in account nesting.
# Example: { int foo(){return 1;} } <- index of this bracket will be returned.
def self.find_index_of_close(open_char, close_char, content)
    level = 1
    index = 0
    while (level != 0)
        if (content[index] == open_char)
            level += 1
        elsif (content[index] == close_char)
            level -= 1
        end
        index += 1
    end
    index - 1
end

# Moves 'immutable' from qualifiers to type.
def self.move_immutable_keyword(qualifiers, type)
    if (qualifiers =~ /immutable/)
        qualifiers.sub!(/immutable/, '')
        type = "immutable #{type}"
    end
    [qualifiers, type]
end

# Gets qualifiers prepeared for alternative block in regualar expression.
def self.get_qualifiers_regexp()
    qualifiers = DSourceParser::get_qualifiers
    qualifiers.join(' |') + ' '
end

# Parses // and /* comments.
def self.parse_comment(content, data)
    if (content =~ /\A\s*\/\*/)
        index = content.index('*/')
        return content[index+2..-1]
    end
    if (content =~ /\A\s*\/\//)
        index = content.index("\n")
        if (index.nil?)
            return ''
        else
            return content[index+1..-1]
        end
    end
    
    content
end

# Parses extern blocks (extern (C) {...}). 
def self.parse_extern(content, data)
    index = (content =~ /\A\s*(private|public)?\s*extern\s*\([^)]+\)\s*{/)
    unless (index)
        return content
    end

    begin_index = content.index('{') + 1
    end_index = find_index_of_close('{', '}', content[begin_index..-1])
    end_index += begin_index - 1

    parse(content[begin_index..end_index], data)
    
    content[end_index+2..-1]
end

# Parses alias and typedef keywords.
def self.parse_alias(content, data)
    index = (content =~ /\A\s*(alias|typedef)\s+([^\s]+)\s+([^\s;]+)\s*;/)
    unless index
        return content
    end
    
    data.current_module.aliases.push SPVariable.new($2, $3, $1, data.current_version)
    index = content.index(';')
    content[index+1..-1]
end

# Parses version keyword.
def self.parse_version(content, data)
    index = (content =~ /\A\s*(else)?\s*version\s*\(([^)]+)\)\s*{/)
    unless (index)
        return content
    end
    name = $2

    prev_version = data.current_version
    data.current_version = name
    
    begin_index = content.index('{') + 1
    end_index = find_index_of_close('{', '}', content[begin_index..-1])
    end_index += begin_index - 1

    parse(content[begin_index..end_index], data)
    
    content = content[end_index+2..-1]
    
    if (content =~ /\A\s*else\s*{/)
        data.current_version = "!#{name}"
        
        begin_index = content.index('{') + 1
        end_index = find_index_of_close('{', '}', content[begin_index..-1])
        end_index += begin_index - 1

        parse(content[begin_index..end_index], data)
        content = content[end_index+2..-1]
    end
    
    data.current_version = prev_version
    content
end

# Parses "import" keyword.
def self.parse_import(content, data)
    unless (content =~ /\A\s*(public|private)?\s*import\s+([^\s;:]+)\s*(:\s*[^;]+)?;/)
        return content
    end
    
    index = content.index(';')
    import_name = $2
    
    if (data.current_module.nil?)
        puts "Current module not specified. Couldn't write import of #{import_name}"
    else
        data.current_module.imports.push import_name
    end
    content[index+1..-1]
end

# Parses "module" keyword.
def self.parse_module(content, data)
    unless (content =~/\A\s*module\s+([^;]+);/)
        return content
    end
    
    module_name = $1
    module_index = data.modules.index {|x| x.name == module_name}
    
    unless (module_index.nil?)
        data.current_module = data.modules[module_index]
    else
        new_module = SPModule.new(module_name)
        data.modules.push new_module
        data.current_module = new_module
    end

    index = content.index(';')    
    content[index+1..-1]
end

# Parses variable declaration.
def self.parse_variable(content, data)
    qualifiers_for_regexp = get_qualifiers_regexp
    regexp = /\A((#{qualifiers_for_regexp})*)\s*(?!import)(((immutable\s*\(\s*[^)\s]+\s*\)(\[|\])*)|[^(\s]+))\s+([^;\s()]+)(\s*=\s*[^;]*\s*)?;/

    index = (content =~ regexp)
    unless (index)
        return content
    end

    qualifiers = $1
    type = $4
    name = $7

    qualifiers, type = move_immutable_keyword(qualifiers, type)

    variable = SPVariable.new(name, type, qualifiers, data.current_version)
    if (data.current_type.nil?)
        data.current_module.variables.push variable
    elsif (data.current_type.instance_of?(SPClass))
        data.current_type.variables.push variable
    end
    
    index = content.index(';')
    return content[index+1..-1]
    
    content
end

# Parses method declaration.
def self.parse_method(content, data)
    qualifiers_for_regexp = get_qualifiers_regexp
    qualifiers_without_immutable = (DSourceParser::get_qualifiers - ['immutable']).join(' |') + ' '
    method_regexp = /\A((#{qualifiers_for_regexp})*)(?!#{qualifiers_without_immutable})\s*(((immutable\s*\([^)]+\)(\[|\])*)|[^(\s]+))\s+([^\s]+)\s*\(([^{;]*)\)(in|out|body|\s)*(\{|;)/
    ctor_regexp = /\A((#{qualifiers_for_regexp})*)\s*(~?this)\s*\(([^{]*)\)(in|out|body|\s)*({|;)/

    # Try parse simple methods.
    index = (content =~ method_regexp)
    if (index)
        qualifiers = $1
        return_type = $4
        method_name = $7
        args = $8
        last_symbol = $10
    else
        # Try parse constructors.
        index = (content =~ ctor_regexp)
        if (index)
            qualifiers = $1
            return_type = ''
            method_name = $3
            args = $4
            last_symbol = $6
        end
    end

    if (index)
        qualifiers, return_type = move_immutable_keyword(qualifiers, return_type)
        method = SPMethod.new(method_name, return_type, qualifiers, args, data.current_version)
        
        if (data.current_type.nil?)
            data.current_module.methods.push method
        elsif (data.current_type.instance_of?(SPClass))
            data.current_type.methods.push method
        end

        if (last_symbol == '{')
            # Skip contract methods (by in, out, body keywords).
            open_bracket_index = content.index('{')
            close_bracket_index = find_index_of_close('{', '}', content[open_bracket_index+1..-1]) + open_bracket_index + 1
            open_bracket_index = content.index('{', close_bracket_index+1)
            
            while (!open_bracket_index.nil? && content[close_bracket_index..open_bracket_index] =~ /}\s*(body|in|out)\s*{/)
                close_bracket_index = content.index('}', close_bracket_index+1)
                open_bracket_index = content.index('{', open_bracket_index+1)
            end
        else
            close_bracket_index = content.index(';')
        end

        return content[close_bracket_index+1..-1]
    end
    content
end

# Parses enum declaration.
def self.parse_enum(content, data)
    qualifiers_for_regexp = get_qualifiers_regexp
    
    index = (content =~ /\A((#{qualifiers_for_regexp})*)\s*enum\s+([^{:\s]+)\s*(:\s*([^{]+))?{/)
    unless (index)
        return content
    end

    qualifiers = $1
    name = $3
    base_type = $5
    
    # Get class content and then parse it.
    begin_index = content.index('{') + 1
    end_index = find_index_of_close('{', '}', content[begin_index..-1])
    end_index += begin_index - 1
    
    values = []
    enum_content = content[begin_index..end_index]
    while (enum_content != '')
        prev_content = enum_content
        enum_content = parse_comment(enum_content, data)
        enum_content.strip!
        if (enum_content =~ /\A\s*([^,]+),?/)
            values.push $1.split.join(' ')
            index = enum_content.index(',')
            enum_content = (index.nil? ? '' : enum_content[index+1..-1])
        end
        if (enum_content == prev_content)
            index = enum_content.index("\n")
            puts "Cannot parse line for enum: #{enum_content[0..(index.nil? ? -1 : index)]}"
            enum_content = (index.nil? ? '' : enum_content[index+1..-1])
        end
    end
    
    new_enum = SPEnum.new(name, data.current_module, values, base_type, qualifiers, data.current_version)
    data.current_module.types.push new_enum

    content[end_index+2..-1]
end

# Parses class declaration.
def self.parse_class(content, data)
    qualifiers_for_regexp = get_qualifiers_regexp

    index = (content =~ /\A((#{qualifiers_for_regexp})*)\s*(class|struct)\s+([^{:\s]+)\s*(:\s*([^{]+))?{/)
    unless (index)
        return content
    end
    qualifiers = $1
    class_name = $4
    base_types = $6

    unless (base_types.nil?)
        base_types = base_types.split(',')
        base_types.each do |t|
            t.strip!
        end
    end

    new_class = SPClass.new(class_name, data.current_module, qualifiers, base_types, data.current_version)
    prev_type = data.current_type
    data.current_type = new_class
    data.current_module.types.push new_class
    
    # Get class content and then parse it.
    begin_index = content.index('{') + 1
    end_index = find_index_of_close('{', '}', content[begin_index..-1])
    end_index += begin_index - 1
    
    parse(content[begin_index..end_index], data)
    data.current_type = prev_type

    content[end_index+2..-1]
end

# Parses @content.
def self.parse(content, data)
    # Order of methods is important because code like that: //return 0;
    # Maybe parsed as variable declaration.
    methods = [lambda { parse_comment(content, data) }, lambda { parse_version(content, data) },
        lambda { parse_extern(content, data) }, lambda { parse_alias(content, data) },
        lambda { parse_module(content, data) }, lambda { parse_import(content, data) }, 
        lambda { parse_class(content, data) }, lambda { parse_enum(content, data) },
        lambda { parse_method(content, data) }, lambda { parse_variable(content, data) }]

    while (content != '')
        initial_content = content
        
        methods.each do |method|
            content = method.call()
            content.strip!
            break if (initial_content != content)
        end

        if (initial_content == content)
            index = content.index("\n")
            puts "Cannot parse line: #{content[0..(index.nil? ? -1 : index)]}"
            content = (index.nil? ? '' : content[index+1..-1])
        end
    end
end

# Parses file with name @file_name.
def self.parse_file(file_name, data)
	content = ''
	File.open(file_name, 'r') do |file|
		while (line = file.gets)
            content += line
        end
	end
    content.strip!

    parse(content, data)
    
    index = data.modules.index do |item|
        item.name == 'global'
    end
    data.current_module = data.modules[index]
end

def self.draw_methods(graph, methods)
    methods.each do |x|
        graph = GraphvizUML::add_function(graph, x.name, x.qualifiers, x.return_type, x.arguments, x.version)
    end
    graph
end

def self.draw_variables(graph, variables)
    variables.each do |v|
        graph = GraphvizUML::add_variable(graph, v.name, v.qualifiers, v.type, v.version)
    end
    graph
end

# Draws defined types.
def self.draw_types(graph, data)
    data.modules.each do |m|
        graph = GraphvizUML::open_package(graph, m.name)
        
        if (m.aliases.length > 0)
            graph = GraphvizUML::open_class(graph, "alias__#{m.name}", '', '', '')
            graph = GraphvizUML::add_separator(graph)
            m.aliases.each do |a|
                graph = GraphvizUML::add_string(graph, "#{a.qualifiers} #{a.name} #{a.type}")
            end
            graph = GraphvizUML::close_element(graph)
        end
        
        # Draw module's methods and variables.
        if (m.variables.length > 0 || m.methods.length > 0)
            graph = GraphvizUML::open_class(graph, "module__#{m.name}", '', '', '')
            graph = GraphvizUML::add_separator(graph)
            graph = draw_variables(graph, m.variables)
            graph = GraphvizUML::add_separator(graph)
            graph = draw_methods(graph, m.methods)
            graph = GraphvizUML::close_element(graph)
        end
        
        # Draws each type.
        m.types.each do |t|
            if (t.instance_of?(SPEnum))
                graph = GraphvizUML::open_enum(graph, t.name, t.qualifiers, t.values, t.version)
                graph = GraphvizUML::close_element(graph)
            elsif (t.instance_of?(SPClass))
                base_types = t.base_types.join(',')
                graph = GraphvizUML::open_class(graph, t.name, t.qualifiers, base_types, t.version)
                graph = GraphvizUML::add_separator(graph)
                graph = draw_variables(graph, t.variables)
                graph = GraphvizUML::add_separator(graph)
                graph = draw_methods(graph, t.methods)
                graph = GraphvizUML::close_element(graph)
            end
        end
        graph = GraphvizUML::close_package(graph)
    end
    graph
end

# Draws relationships between defined types.
def self.draw_relationship_tree(graph, data)
    types = data.get_all_types
    graph = GraphvizUML::set_inheritance_arrow_mode graph
    types.each do |t|
        if (t.instance_of?(SPClass))
            t.base_types.each do |b|
                if(types.index {|x|x.name == b})
                    graph = GraphvizUML::add_base_type(graph, t.name, b)
                end
            end
        end
    end
    
    graph = GraphvizUML::set_composition_arrow_mode graph
    composition_map = []
    types.each do |t|
        if (t.instance_of?(SPClass))
            t.variables.each do |v|
                index = types.index {|x|v.type =~ /\A(immutable|\()*\s*#{x.name}(\[|\]|\)|\*)*\z/}
                if (index && !composition_map.index{|item| item[0] == t.name && item[1] == types[index].name})
                    composition_map.push [t.name, types[index].name]
                end
            end
        end
    end
    composition_map.each do |item|
        graph = GraphvizUML::add_composition(graph, item[0], item[1])
    end
    
    graph
end

def self.main(files)
    image_file = File.join(Dir.pwd, 'graph.png')
    graph_file = File.join(Dir.pwd, 'graph.out')

    # Specified files add without changes.
    # Specified directories scan for .d files recursively.
    new_files = []
    files.each do |f|
        if (File.directory? f)
            Dir.chdir f
            found_files = Dir.glob(File.join('**', "*.d"))
            unless found_files.length == 0
                found_files.each do |found_file|
                    new_files.push File.join(Dir.pwd, found_file)
                end
            end
        else
            unless File.exists? f
                puts "File #{f} not exists."
            else
                new_files.push f
            end
        end
    end
    files = new_files
    
    if (files.length == 0)
        puts 'Files to parse not specified.'
        return
    end

    data = TypesTree.new

    files.each do |file|
        parse_file(file, data)
    end

    graph = GraphvizUML::init_graph
    
    graph = draw_types(graph, data)
    graph = draw_relationship_tree(graph, data)

    File.open(graph_file, 'w') do |file|
        file.puts "#{graph} }"
    end
    system("dot -Tpng #{graph_file} -o #{image_file}")
end

main ARGV
    
end
