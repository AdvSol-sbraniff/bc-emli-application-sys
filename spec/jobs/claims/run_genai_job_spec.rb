require "rails_helper"

RSpec.describe Claims::RunGenaiJob do
  describe "#advice_from_rulechecks" do
    it "labels a non-blocking caveat as info without calling it a note" do
      advice =
        described_class.new.send(
          :advice_from_rulechecks,
          {
            "rulechecks" => [
              {
                "rule_key" => "sample_rule",
                "rule_result" => "info",
                "reason_and_likely_causes" =>
                  "The requirement is met, but a specific caveat prevents a clean pass."
              }
            ]
          }
        )

      expect(advice).to eq(
        "- sample_rule: Info: The requirement is met, but a specific caveat prevents a clean pass."
      )
      expect(advice).not_to match(/note/i)
    end
  end
end
