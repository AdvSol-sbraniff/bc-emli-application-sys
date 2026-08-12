require "rails_helper"

RSpec.describe "AWS credential jobs outside S3 storage" do
  it "skips credential refresh without constructing the AWS service" do
    expect(AwsCredentialRefreshService).not_to receive(:new)

    expect(AwsCredentialRefreshJob.perform_now).to be_nil
  end

  it "reports a skipped health check without constructing the AWS service" do
    expect(AwsCredentialRefreshService).not_to receive(:new)

    expect(AwsCredentialHealthCheckJob.perform_now).to eq(
      skipped: true,
      reason: "s3_storage_disabled"
    )
  end
end
