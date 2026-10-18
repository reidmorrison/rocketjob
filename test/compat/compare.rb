# Compares the results of the v7 and v8 runs of the compatibility harness, see README.md. Plain Ruby, without a
# bundle, from the root of the repository:
#
#   ruby test/compat/compare.rb all              write every comparison to <results>/compare-<name>.txt
#   ruby test/compat/compare.rb matrix           print one, see Compat::Comparison::ALL
#   ruby test/compat/compare.rb versus OTHER_DIR compare the v8 matrix of another results directory with this one's
#
# The results are in tmp/compat, unless COMPAT_RESULTS names another directory.
require_relative "support/paths"
require_relative "support/comparison"

name, other = ARGV
comparison  = Compat::Comparison.new(Compat::Paths.results)

if name.nil? || name == "all"
  Compat::Comparison::ALL.each do |each_name|
    lines = comparison.report(each_name)
    path  = Compat::Paths.result("compare-#{each_name}.txt")
    File.write(path, lines.join("\n") + "\n")
    puts "#{path}: #{Compat::Comparison::PAIRS.key?(each_name) ? lines.first : "#{lines.size} lines"}"
  end
else
  puts comparison.report(name, other)
end
