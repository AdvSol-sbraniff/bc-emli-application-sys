# app/services/claims/sessions/create.rb
module Claims
  module Sessions
    class Create
      Result = Struct.new(:session)

      def self.call(contractor_id:)
        new(contractor_id: contractor_id).call
      end

      def initialize(contractor_id:)
        @contractor_id = contractor_id
      end

      def call
        now = Time.zone.now

Rails.logger.info("[CLAIMS][SESSIONS_CREATE] contractor_id=#{@contractor_id} starting create")

        session = ::Claims::Session.create!(
          contractor_id: @contractor_id,
          submitter_id: nil,
          status: "OPENBUTNOTSUBMITTED",
          submitted_at: nil,
          created_at: now,
          updated_at: now
        )

        Result.new(session)
      end
    end
  end
end
