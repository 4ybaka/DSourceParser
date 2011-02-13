#!/usr/bin/env ruby

require 'optparse'
require File.expand_path('../graphviz', __FILE__)
require File.expand_path('../d_source_parser_types', __FILE__)

module DSourceParser

# TODO: Create map to replace "aliased" types.
# TODO: extern(C) int method(..)
# TODO: Process parsed extern keyword content.
# TODO: Parse qualifiers only in class content.
# TODO: alias maybe be declared inside class defenition.
# TODO: Cannot parse array declaration where in calculation of its length used brackets (int[(maxSize+1)/2] a;)

# Concatenates 2 strings that maybe nil.
def self.concat_strings(str1, str2)
    (str1.nil? ? '' : str1 + ' ') + (str2.nil? ? '' : str2)
end

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

    # Parses TODO comments. Supported only one-line comments started with //.
    def self.parse_todo(content, data)
        if content =~ /(todo\s*:\s*([^\n]+))/i
            data.context.module.todo.push $2
        end
    end

    if (content =~ /\A\s*\/\*/)
        index = content.index('*/')
        parse_todo(content[0..index], data)
        return parse_comment(content[index+2..-1], data)
    end
    if (content =~ /\A\s*\/\//)
        index = content.index("\n")
        if (index.nil?)
            return ''
        else
            parse_todo(content[0..index], data)
            return parse_comment(content[index+1..-1], data)
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
    index = (content =~ /\A\s*(public|private)?\s*(alias|typedef)\s+([^\s]+)\s+([^\s;]+)\s*;/)
    unless index
        return content
    end
    
    qualifiers = concat_strings(GraphvizUML::get_scope($1), $2)
    data.context.module.aliases.push SPVariable.new($3, $4, qualifiers, data.context.version)
    index = content.index(';')
    content[index+1..-1]
end

# Parse qualifiers.
def self.parse_qualifiers(content, data)
    qualifiers = 'private|protected|public|package|static'
    index = (content =~ /\A\s*(#{qualifiers})+\s*(:|{)/)
    unless (index)
        return content
    end

    qualifiers = $1

    if ($2 == ':')
        data.context.qualifiers = qualifiers
        index = content.index(':')
        return content[index+1..-1]        
    end

    prev_qualifiers = data.context.qualifiers
    data.context.qualifiers = qualifiers
    
    begin_index = content.index('{') + 1
    end_index = find_index_of_close('{', '}', content[begin_index..-1])
    end_index += begin_index - 1

    parse(content[begin_index..end_index], data)
    data.context.qualifiers = prev_qualifiers
    
    content[end_index+2..-1]
end

# Parses version keyword.
def self.parse_version(content, data)
    index = (content =~ /\A\s*(else)?\s*version\s*\(([^)]+)\)\s*{/)
    unless (index)
        return content
    end
    name = $2

    prev_version = data.context.version
    data.context.version = name
    
    begin_index = content.index('{') + 1
    end_index = find_index_of_close('{', '}', content[begin_index..-1])
    end_index += begin_index - 1

    parse(content[begin_index..end_index], data)
    
    content = content[end_index+2..-1]
    
    if (content =~ /\A\s*else\s*{/)
        data.context.version = "!#{name}"
        
        begin_index = content.index('{') + 1
        end_index = find_index_of_close('{', '}', content[begin_index..-1])
        end_index += begin_index - 1

        parse(content[begin_index..end_index], data)
        content = content[end_index+2..-1]
    end
    
    data.context.version = prev_version
    content
end

# Parses "import" keyword.
def self.parse_import(content, data)
    unless (content =~ /\A\s*(public|private)?\s*import\s+([^;:]+)\s*(:\s*[^;]+)?;/)
        return content
    end
    
    index = content.index(';')
    import_name = $2.strip
    functions = $3
    
    if (functions)
        import_name = import_name + functions.split.join(' ')
    end
    
    if (data.context.module.nil?)
        puts "Current module not specified. Couldn't write import of #{import_name}"
    else
        data.context.module.imports.push import_name
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
        data.context.module = data.modules[module_index]
    else
        new_module = SPModule.new(module_name)
        data.modules.push new_module
        data.context.module = new_module
    end
    data.context.qualifiers = ''

    index = content.index(';')    
    content[index+1..-1]
end

# Parses variable declaration.
def self.parse_variable(content, data)
    qualifiers_for_regexp = get_qualifiers_regexp
    regexp = /\A\s*((#{qualifiers_for_regexp})*)\s*(?!import)(((immutable\s*\(\s*[^)\s]+\s*\)(\[[^\]]*\])?)|[^(\s]+))\s+([^;\s()]+)(\s*=\s*[^;]*\s*)?;/

    index = (content =~ regexp)
    unless (index)
        return content
    end

    qualifiers = concat_strings($1, data.context.qualifiers)
    type = $4
    name = $7

    qualifiers, type = move_immutable_keyword(qualifiers, type)

    variable = SPVariable.new(name, type, qualifiers, data.context.version)
    if (data.context.type.nil?)
        data.context.module.variables.push variable
    else
        data.context.type.variables.push variable
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
        qualifiers = concat_strings($1, data.context.qualifiers)
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
        method = SPMethod.new(method_name, return_type, qualifiers, args, data.context.version)
        
        if (data.context.type.nil?)
            data.context.module.methods.push method
        elsif (data.context.type.instance_of?(SPClass))
            data.context.type.methods.push method
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

# Parses union declaration.
def self.parse_union(content, data)
    qualifiers_for_regexp = get_qualifiers_regexp
    
    index = (content =~ /\A((#{qualifiers_for_regexp})*)\s*union\s+([^{:\s]+)\s*{/)
    unless (index)
        return content
    end
    
    qualifiers = concat_strings($1, data.context.qualifiers)
    name = $3
    
    new_union = SPUnion.new(name, data.context.module, qualifiers, data.context.version)
    prev_type = data.context.type
    data.context.type = new_union
    
    # Get union content and then parse it.
    begin_index = content.index('{') + 1
    end_index = find_index_of_close('{', '}', content[begin_index..-1])
    end_index += begin_index - 1
    
    values = []
    union_content = content[begin_index..end_index]
    while (union_content != '')
        prev_content = union_content
        union_content = parse_comment(union_content, data)
        union_content.strip!
        
        union_content = parse_variable(union_content, data)
        if (union_content == prev_content)
            index = union_content.index("\n")
            puts "Cannot parse line for union: #{union_content[0..(index.nil? ? -1 : index)]}"
            union_content = (index.nil? ? '' : union_content[index+1..-1])
        end
    end
    
    data.context.type = prev_type
    data.context.module.types.push new_union

    content[end_index+2..-1]
end

# Parses enum declaration.
def self.parse_enum(content, data)
    qualifiers_for_regexp = get_qualifiers_regexp
    
    index = (content =~ /\A((#{qualifiers_for_regexp})*)\s*enum\s+([^{:\s]+)\s*(:\s*([^{]+))?{/)
    unless (index)
        return content
    end

    qualifiers = concat_strings($1, data.context.qualifiers)
    name = $3
    base_type = $5
    
    # Get enum content and then parse it.
    begin_index = content.index('{') + 1
    end_index = find_index_of_close('{', '}', content[begin_index..-1])
    end_index += begin_index - 1
    
    values = []
    enum_content = content[begin_index..end_index]
    while (enum_content != '')
        prev_content = enum_content
        enum_content = parse_comment(enum_content, data)

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
    
    new_enum = SPEnum.new(name, data.context.module, values, base_type, qualifiers, data.context.version)
    data.context.module.types.push new_enum

    content[end_index+2..-1]
end

# Parses class declaration.
def self.parse_class(content, data)
    qualifiers_for_regexp = get_qualifiers_regexp

    index = (content =~ /\A((#{qualifiers_for_regexp})*)\s*(class|struct)\s+([^{:\s]+)\s*(:\s*([^{]+))?{/)
    unless (index)
        return content
    end
    qualifiers = concat_strings($1, data.context.qualifiers)
    class_name = $4
    base_types = $6

    unless (base_types.nil?)
        base_types = base_types.split(',')
        base_types.each do |t|
            t.strip!
        end
    end

    new_class = SPClass.new(class_name, data.context.module, qualifiers, base_types, data.context.version)
    prev_type = data.context.type
    prev_qualifiers = data.context.qualifiers
    data.context.type = new_class
    data.context.module.types.push new_class
    data.context.qualifiers = ''
    
    # Get class content and then parse it.
    begin_index = content.index('{') + 1
    end_index = find_index_of_close('{', '}', content[begin_index..-1])
    end_index += begin_index - 1
    
    parse(content[begin_index..end_index], data)
    data.context.type = prev_type
    data.context.qualifiers = prev_qualifiers

    content[end_index+2..-1]
end

# Parses @content.
def self.parse(content, data)
    # Order of methods is important because code like that: //return 0;
    # Maybe parsed as variable declaration.
    methods = [lambda { parse_comment(content, data) }, lambda { parse_version(content, data) },
        lambda { parse_extern(content, data) }, lambda { parse_alias(content, data) },
        lambda { parse_module(content, data) }, lambda { parse_import(content, data) },
        lambda { parse_qualifiers(content, data) },
        lambda { parse_class(content, data) }, 
        lambda { parse_enum(content, data) }, lambda { parse_union(content, data) },
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
    data.context.module = data.modules[index]
end

# Draws defined types.
def self.draw_types(graph, data, draw_options)
    data.modules.each do |m|
        graph = GraphvizUML::open_package(graph, m.name)

        # Draw todo list.
        if (m.todo.length > 0 && (draw_options == '*' || draw_options.index('t')))
            graph = GraphvizUML::open_element(graph, "todo__#{m.name}", "TODO__#{m.name}", [['color', 'dimgray'], ['fontcolor', 'dimgray']])
            graph = GraphvizUML::add_separator(graph)
            m.todo.each do |todo|
                graph = GraphvizUML::add_string(graph, todo)
            end
            graph = GraphvizUML::close_element(graph)
        end
        
        # Draw alias.
        if (m.aliases.length > 0 && (draw_options == '*' || draw_options.index('a')))
            graph = GraphvizUML::open_element(graph, "alias__#{m.name}", "alias__#{m.name}")
            graph = GraphvizUML::add_separator(graph)
            m.aliases.each do |a|
                graph = GraphvizUML::add_string(graph, "#{a.qualifiers} #{a.name} #{a.type}")
            end
            graph = GraphvizUML::close_element(graph)
        end
        
        # Draw module's methods and variables.
        if ((m.variables.length > 0 || m.methods.length > 0) && (draw_options == '*' || draw_options.index('m')))
            graph = GraphvizUML::open_element(graph, "module__#{m.name}", "module__#{m.name}")
            graph = GraphvizUML::add_separator(graph)
            graph = GraphvizUML::add_variables(graph, m.variables)
            graph = GraphvizUML::add_separator(graph)
            graph = GraphvizUML::add_functions(graph, m.methods)
            graph = GraphvizUML::close_element(graph)
        end
        
        # Draws each type.
        m.types.each do |t|
            if (t.instance_of?(SPEnum))
                graph = GraphvizUML::add_enum(graph, t)
            elsif (t.instance_of?(SPClass))
                graph = GraphvizUML::add_class(graph, t)
            elsif (t.instance_of?(SPUnion))
                graph = GraphvizUML::add_union(graph, t)
            end
        end
        graph = GraphvizUML::close_package(graph)
    end
    graph
end

# Draws relationships between defined types.
def self.draw_relationship_tree(graph, data, draw_options)
    types = data.get_all_types
    if (draw_options == '*' || draw_options.index('i'))
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
    end
    
    if (draw_options == '*' || draw_options.index('c'))
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
    end
    
    graph
end

def self.main(files, draw_options, print_file_name)
    start_dir = Dir.pwd
    image_file = File.join(start_dir, 'graph.png')
    graph_file = File.join(start_dir, 'graph.out')

    # Specified files add without changes.
    # Specified directories scan for .d files recursively.
    new_files = []
    files.each do |f|
        Dir.chdir start_dir
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
        puts "Parsing #{file}..." if print_file_name
        parse_file(file, data)
    end

    graph = GraphvizUML::init_graph
    
    graph = draw_types(graph, data, draw_options)
    graph = draw_relationship_tree(graph, data, draw_options)

    File.open(graph_file, 'w') do |file|
        file.puts "#{graph} }"
    end
    system("dot -Tpng #{graph_file} -o #{image_file}")
end

options = Hash[:d, '*']
OptionParser.new do |opts|
    opts.banner = 'Usage: d_source_parser.rb -d[draw options] -f[files]'
    
    opts.on('-d [options]', 'Draw options: [c]omposition, [i]nheritance, [a]liases, [m]odule\'s data, [t]odo list.') do |d|
        options[:d] = d
    end

    opts.on('-f file1,dir1', Array, 'Files to parse.') do |f|
        options[:f] = f
    end
    
    opts.on('-p', 'Print file names during it\'s content is parsing.') do |p|
        options[:p] = p
    end
end.parse!

unless (options[:f])
    puts 'Files to parse not specified.'
    exit
end

main(options[:f], options[:d], options[:p])
    
end
