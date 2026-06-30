require "psych/visitors/yaml_tree"

module Psych
  module Visitors
    class YAMLTree
      # Serialize IOStream path as a string
      def visit_IOStreams_Path(o)
        visit_String(o.to_s)
      end
    end
  end
end
