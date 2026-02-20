# sbraniff_scripts/genai_test.rb
require "net/http"
require "json"

system_text      = File.read(File.join(__dir__, "system_prompt.txt")).strip
groundtruth_text = File.read(File.join(__dir__, "groundtruth.txt")).strip
currentcase_text = File.read(File.join(__dir__, "currentcase.txt")).strip
di_json_text     = File.read(File.join(__dir__, "output-di-call.json")).strip
actualask_text   = File.read(File.join(__dir__, "actualask.txt")).strip

currentcase_text = currentcase_text + "\n\n---\n\n" + di_json_text

cw = [
  { role: "system", content: [{ type: "input_text", text: system_text }] },
  { role: "user",   content: [{ type: "input_text", text: groundtruth_text }] },
  { role: "user",   content: [{ type: "input_text", text: currentcase_text }] },
  { role: "user",   content: [{ type: "input_text", text: actualask_text }] }
]

payload = { contextwindowjson: cw }

uri = URI("http://host.docker.internal:3001/inv/genai")
res = Net::HTTP.post(uri, payload.to_json, { "Content-Type" => "application/json" })

puts res.code

out_path = File.join(__dir__, "assistant_reply.json")

if res.code.to_i >= 200 && res.code.to_i < 300
  # validate + pretty-print
  parsed = JSON.parse(res.body)
  File.write(out_path, JSON.pretty_generate(parsed) + "\n")
  puts "Wrote: #{out_path}"
else
  # save error body too (still useful)
  File.write(out_path, res.body + "\n")
  puts "Non-2xx response; wrote raw body to: #{out_path}"
  puts res.body
end