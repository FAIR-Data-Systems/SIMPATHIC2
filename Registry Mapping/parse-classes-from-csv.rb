
require 'csv'
require 'erb'

# Step 1: Generate the unique identifiers
start_num = 12
end_num = 14500
prefix = "MotFunc_"
identifiers = (start_num..end_num).map { |num| "#{prefix}%05d" % num }

# Step 2: Read the first column from the input CSV
input_file = 'data.csv'  # Replace with your input CSV file path
first_column_values = []
begin
  first_column_values = CSV.foreach(input_file, headers: true).map { |row| row[0] if row[0] }
rescue Errno::ENOENT
  puts "Error: Input file '#{input_file}' not found."
  exit
rescue CSV::MalformedCSVError => e
  puts "Error: Invalid CSV format in '#{input_file}' - #{e.message}"
  exit
end



classs = File.read "./templates/_toplevel.erb"
header = File.read "./templates/_header.erb"
footer = File.read "./templates/_footer.erb"
@prefix = "https://w3id.org/nmd-domain#"

top = {}
f = File.open("test.owl", "w")

owl = ERB.new(header).result
f.write owl + "\n\n"


# top categories come from first column
first_column_values.each do |label|
  next unless label
  next if top.keys.include? label  # already seen?
  @funcid = identifiers.shift  # get the next id from the stack
  top[label] = @funcid
  @parent = "http://purl.obolibrary.org/obo/NCIT_C20993"
  @classlabel = label
  # use ERB template
  owl = ERB.new(classs).result
  f.write owl + "\n\n"
end

# now do the individual repos
CSV.foreach(input_file, headers: true) do |row| # row[0] }
  next unless row[0]
  @parent = "#{@prefix}#{top[row[0]]}"
  @funcid = identifiers.shift
  @enmdlabel = row[1]; @enmddef = row[2]
  @dmslabel = row[3]; @dmsdef = row[4]
  @enddm1label = row[5]; @enddm1def = row[6]
  @myodraftlabel = row[7]; @myodraftdef = row[8]
  @hpolabel = row[11]; @hpo = row[12]

  @label = ""
  @label = @hpolabel if  @hpolabel
  @label = @dmslabel if  @dmslabel
  @label = @enmdlabel if  @enmdlabel
  @label = @myodraftlabel if @myodraftlabel
  @label = @enddm1label if @enddm1label
  abort "label empty" unless @label
  abort "label empty" if @label.empty?
  @classlabel = @label

  @description = ""
  @description = @description + "EURO-NMD: " + @enmddef + "; " if @enmddef
  @description = @description + "DM-Scope: " + @dmsdef + "; " if @dmsdef
  @description = @description + "END-DM1: " + @enddm1def + "; " if @enddm1def
  @description = @description + "Myodraft: " + @myodraftdef + "; " if @myodraftdef
  @description = @description + "HPO: " + @hpo + " " + @hpolabel + "; " if @hpo
  abort "description empty" if  @description.empty?


  # @metadata = ""
  # @metadata = @metadata + "Myodraft: #{@myodraftlabel}</dc:identifier>\n"  if @myodraftlabel
  # @metadata = @metadata + "END-DM1: #{@enddm1label}</dc:identifier>\n"  if @enddm1label
  # @metadata = @metadata + "DM-Scope: #{@dmslabel}</dc:identifier>\n"  if @dmslabel
  # @metadata = @metadata + "EURO-NMD: #{@enmdlabel}</dc:identifier>\n"  if @enmdlabel
  # @metadata = @metadata + "<dc:identifier>HPO: #{@hpo}</dc:identifier>\n"  if @hpo
  
  # use ERB template
  owl = ERB.new(classs).result
  f.write owl + "\n\n"
end

owl = ERB.new(footer).result
f.write owl + "\n\n"

puts "last identifier", identifiers.shift


