module GraphvizUML

    # Gets base string for graph.
	def self.init_graph
		return "digraph G {
		fontname = \"Bitstream Vera Sans\"
		fontsize = 8

		node [
			fontname = \"Bitstream Vera Sans\"
		    fontsize = 8
		    shape = \"record\"
		]

		edge [
		    fontname = \"Bitstream Vera Sans\"
		    fontsize = 8
		]"
	end
	
    # Adds all necessary data to close currently openned element.
	def self.close_element(graph)
		graph + "}\"]"
	end
    
    # Adds all necessary data to close currently openned package.
	def self.close_package(graph)
		graph + '}'
	end

    # Adds package to the graph.
    def self.open_package(graph, package_name)
        graph + " subgraph cluster_#{package_name.gsub(/\./, '_')} { label=\"#{package_name}\";"
    end
    
    # Adds element to the graph.
	def self.open_element(graph, name, visible_name)
		graph + "#{name.gsub(/\./, '_')} [ \nlabel = \"{#{visible_name}"
	end
    
    # Adds class to the graph.
    def self.add_class(graph, cl)
        base_types = get_base_types cl.base_types
        scope = get_scope cl.qualifiers
        version = get_version cl.version
        
        graph = open_element(graph, cl.name, "#{scope}#{cl.name}#{base_types}#{version}")
        graph = add_separator(graph)
        graph = add_variables(graph, cl.variables)
        graph = add_separator(graph)
        graph = add_functions(graph, cl.methods)
        graph = close_element(graph)
    end
	
    # Adds enum to the graph.
	def self.add_enum(graph, enum)
        scope = get_scope enum.qualifiers
		version = get_version enum.version
        
        graph += "#{enum.name} [ \nlabel = \"{#{scope}enum #{enum.name}#{version}|"
		enum.values.each { |e|
            graph += "#{e}\\l"
        }
        close_element graph
	end
    
    # Adds union to the graph.
	def self.add_union(graph, union)
        scope = get_scope union.qualifiers
		version = get_version union.version
        
        graph += "#{union.name} [ \nlabel = \"{#{scope}union #{union.name}#{version}|"
		union.variables.each { |u|
            graph = add_variable(graph, u.name, u.qualifiers, u.type, u.version)
        }
        close_element graph
	end
    
    # Adds functions to currently openned element.
    def self.add_functions(graph, functions)
        functions.each do |x|
            graph = GraphvizUML::add_function(graph, x.name, x.qualifiers, x.return_type, x.arguments, x.version)
        end
        graph
    end

    # Adds function to currently openned element.
	def self.add_function(graph, name, qualifiers, return_type, args, version)
		scope = get_scope qualifiers
        version = get_version version
		graph + "#{scope}#{name}(#{args}) : #{return_type}#{version}\\l"
	end
	
    # Adds variables to currently openned element.
    def self.add_variables(graph, variables)
        variables.each do |v|
            graph = add_variable(graph, v.name, v.qualifiers, v.type, v.version)
        end
        graph
    end
    
    # Adds variable to currently openned element.
	def self.add_variable(graph, name, qualifiers, type, version)
		scope = get_scope qualifiers
        version = get_version version
		graph + "#{scope}#{name} : #{type}#{version}\\l"
	end

    # Adds string to currently openned element.
	def self.add_string(graph, string)
		graph + "#{string}\\l"
	end
    
    # Adds separator to currently openned element.
    def self.add_separator(graph)
        graph + '|'
    end
    
    # Adds arrow from inheritor to base type.
    def self.add_base_type(graph, child_type, base_type)
        graph + " #{child_type}->#{base_type}; "
    end

    # Adds composition links.
    def self.add_composition(graph, type, contained_type)
        graph + " #{contained_type}->#{type}; "
    end
    
    # Makes graph ready to display composition relationships.
    def self.set_composition_arrow_mode(graph)
        graph + ' edge [arrowhead = "normalinv"] '
    end
    
    # Makes graph ready to display inheritance relationships.
    def self.set_inheritance_arrow_mode(graph)
        graph + ' edge [arrowhead = "onormal"] '
    end
    
    private
    
    def self.get_base_types(types)
        if types.length == 0
            return ''
        end
        types = ' : ' + types.join(',')
    end
    
    def self.get_version(version)
        if version.nil? || version.length == 0
            ''
        else
            " ? #{version}"
        end
    end

	def self.get_scope(scope)
        if (scope.index 'private')
            '- '
        elsif (scope.index 'protected')
            '# '
        elsif (scope.index 'package')
            '! '
        elsif (scope.index 'public')
            '+ '
        else
            #puts "Unrecognized object scope: #{scope}"
            ''
        end
	end
end
