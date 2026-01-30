# script/genai_test.rb
require "net/http"
require "json"

system_text = File.read(File.join(__dir__, "system_prompt.txt")).strip

cw = [
  { role: "system", content: [{ type: "input_text", text: system_text }] },
  { role: "user", content: [{ type: "input_text", text: "Return exactly this JSON shape: {\"greeting\":\"string\"}. Set greeting to a friendly hello to Stephen." }] }
]

payload = { contextwindowjson: cw }

uri = URI("http://host.docker.internal:3001/inv/genai")
res = Net::HTTP.post(uri, payload.to_json, { "Content-Type" => "application/json" })

puts res.code
puts res.body
