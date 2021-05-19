require "psych/visitors/yaml_tree"

class Psych::Visitors::YAMLTree
  # Serialize IOStream path as a string
  def visit_IOStreams_Path(o)
    visit_String(o.to_s)
  end
end
