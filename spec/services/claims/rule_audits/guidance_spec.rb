require "rails_helper"
require "tmpdir"

RSpec.describe Claims::RuleAudits::Guidance do
  it "loads the current actual React guidance for both rule engines without invented metric values" do
    %w[genai code].each do |engine|
      reference = described_class.for_engine(engine)
      expect(reference["process_steps"].map { |s| s["number"] }).to eq(
        (1..8).to_a
      )
      expect(reference["improvement_options"].size).to eq(7)
      expect(reference["detailed_help"].map { |s| s["step"] }).to include(
        2,
        3,
        5
      )
      expect(reference.to_json).to include(
        "realworld-checks",
        "published RER policy",
        "What to document"
      )
      expect(
        reference["improvement_options"]
          .flat_map { |option| option["signal_guidance"] }
          .any? { |s| s.key?("value") || s.key?("invoiceCount") }
      ).to be(false)
    end
  end

  it "fails closed after maintained guidance changes without regeneration" do
    Dir.mktmpdir("rule-audit-guidance") do |directory|
      root = Pathname.new(directory)
      root.join("config/claims").mkpath
      root.join("guide.ts").write("original")
      root.join("config/claims/rule_improvement_guidance.json").write(
        {
          sources: {
            "guide.ts" => Digest::SHA256.hexdigest("original")
          },
          engines: {
            genai: {
            }
          }
        }.to_json
      )
      allow(Rails).to receive(:root).and_return(root)
      expect(described_class.for_engine("genai")).to include("reference_sha256")
      root.join("guide.ts").write("changed business guidance")
      expect { described_class.for_engine("genai") }.to raise_error(
        described_class::Unavailable,
        /needs updating/
      )
    end
  end
end
