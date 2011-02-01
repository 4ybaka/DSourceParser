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
	
    # Adds package to the graph.
    def self.open_package(graph, package_name)
        graph + " subgraph cluster_#{package_name.gsub(/\./, '_')} { label=\"#{package_name}\";"
    end
    
    # Adds class to the graph.
	def self.open_class(graph, name, qualifiers, base_class, version)
		if !base_class.nil? && base_class != ''
			base_class = ' : ' + base_class
		end
		
		scope = get_scope qualifiers
        version = get_version version
		
		graph + "#{name.gsub(/\./, '_')} [ \nlabel = \"{#{scope}#{name}#{base_class}#{version}"
	end
	
    # Adds enum to the graph.
	def self.open_enum(graph, name, qualifiers, values, version)
        scope = get_scope qualifiers
		version = get_version version
        
        graph += "#{name} [ \nlabel = \"{#{scope}enum #{name}#{version}|"
		values.each { |e|
            graph += "#{e}\\l"
        }
        graph
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

    # Adds function to currently openned element.
	def self.add_function(graph, name, qualifiers, return_type, args, version)
		scope = get_scope qualifiers
        version = get_version version
		graph + "#{scope}#{name}(#{args}) : #{return_type}#{version}\\l"
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
end
