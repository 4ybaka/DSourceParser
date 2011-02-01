module DSourceParser

def self.get_base_types(global_module)
    names = ['void', 'int', 'uint', 'float', 'double', 'string', 'bool',
        'byte', 'ubyte', 'short', 'ushort', 'long', 'ulong', 'cent', 'ucent',
        'real', 'ifloat', 'idouble', 'ireal', 'cfloat', 'cdouble', 'creal',
        'char', 'wchar', 'dchar']
    types = []
    
    names.each do |name|
        types.push(SPType.new(name, global_module))
    end
    types
end

def self.remove_spaces(value)
    value.nil? ? '' : value.split.join(' ')
end

def self.get_qualifiers()
    ['const', 'immutable', 'shared', 'static', 'private',
        'protected', 'package', 'public', 'export', 'pure', 'ref', 'final',
        'override', 'in', 'out', 'inout', 'lazy', 'abstract']
end

class SPVariable
    attr_accessor :name, :type, :qualifiers, :version
    
    def initialize(name, type, qualifiers, version)
        @name = DSourceParser::remove_spaces name
        @type = DSourceParser::remove_spaces type
        @qualifiers = DSourceParser::remove_spaces qualifiers
        @version = DSourceParser::remove_spaces version
    end
end

class SPMethod
    attr_accessor :name, :return_type, :arguments, :qualifiers, :version
    
    def initialize(name, return_type, qualifiers, arguments, version)
        @name = DSourceParser::remove_spaces name
        @return_type = DSourceParser::remove_spaces return_type
        @qualifiers = DSourceParser::remove_spaces qualifiers
        @arguments = DSourceParser::remove_spaces arguments
        @version = DSourceParser::remove_spaces version
    end
end

class SPType
    attr_accessor :name, :module, :version
    
    def initialize(name, declared_module, version)
        @name = DSourceParser::remove_spaces name
        @module = declared_module
        @version = DSourceParser::remove_spaces version
    end
end

class SPClass < SPType
    attr_accessor :methods, :qualifiers, :variables, :base_types
    
    def initialize(name, declared_module, qualifiers, base_types, version)
        super(name, declared_module, version)
        @methods, @variables = [],[]

        @base_types = base_types.nil? ? [] : base_types 
        @qualifiers = DSourceParser::remove_spaces qualifiers
    end
end

class SPEnum < SPType
    attr_accessor :values, :base_type, :qualifiers
    
    def initialize(name, declared_module, values, base_type, qualifiers, version)
        super(name, declared_module, version)
        
        @base_type = DSourceParser::remove_spaces base_type
        @values = values
        @qualifiers = DSourceParser::remove_spaces qualifiers
    end
end

class SPUnion < SPType
    attr_accessor :variables, :qualifiers
    
    def initialize(name, declared_module, qualifiers, version)
        super(name, declared_module, version)
        
        @variables = []
        @qualifiers = DSourceParser::remove_spaces qualifiers
    end
end

class SPModule
    attr_accessor :name, :methods, :variables, :types, :imports, :aliases
    
    def initialize(name)
        @methods, @variables, @types, @imports, @aliases = [],[],[],[],[]
        @name = DSourceParser::remove_spaces name
    end
end

class TypesTree
    attr_accessor :modules, :current_module, :current_type, :current_version
    
    def initialize
        global_module = SPModule.new('global')
        global_module.types = []#DSourceParser::get_base_types(global_module)
        @modules = [global_module]
        @current_module = global_module
    end
    
    def get_all_types()
        types = []
        modules.each do |m|
            m.types.each do |t|
                types.push(t)
            end
        end
        types
    end
end

end
