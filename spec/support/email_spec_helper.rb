# frozen_string_literal: true

# Helper module for testing email delivery
#
# Usage in specs:
#   include EmailSpecHelper
#
#   it "sends email" do
#     expect {
#       SomeMailer.some_email.deliver_now
#     }.to change { emails_sent.count }.by(1)
#
#     expect(last_email.to).to include("user@example.com")
#     expect(last_email.subject).to include("Welcome")
#   end
#
module EmailSpecHelper
  # Returns all delivered emails
  def emails_sent
    ActionMailer::Base.deliveries
  end

  # Returns the last delivered email
  def last_email
    ActionMailer::Base.deliveries.last
  end

  # Returns emails sent to a specific address
  def emails_to(address)
    ActionMailer::Base.deliveries.select { |email| email.to.include?(address) }
  end

  # Returns emails with a specific subject (partial match)
  def emails_with_subject(subject)
    ActionMailer::Base.deliveries.select { |email| email.subject.include?(subject) }
  end

  # Clears all delivered emails
  def clear_emails
    ActionMailer::Base.deliveries.clear
  end

  # Assert that an email was sent to a specific address
  def expect_email_to(address)
    expect(emails_to(address)).not_to be_empty,
      "Expected an email to be sent to #{address}, but none were found. " \
      "Emails sent to: #{emails_sent.flat_map(&:to).join(', ')}"
  end

  # Assert that no email was sent to a specific address
  def expect_no_email_to(address)
    expect(emails_to(address)).to be_empty,
      "Expected no email to be sent to #{address}, but found #{emails_to(address).count}"
  end

  # Assert that an email with a specific subject was sent
  def expect_email_with_subject(subject)
    expect(emails_with_subject(subject)).not_to be_empty,
      "Expected an email with subject containing '#{subject}', but none were found. " \
      "Subjects: #{emails_sent.map(&:subject).join(', ')}"
  end
end

RSpec.configure do |config|
  config.include EmailSpecHelper, type: :mailer
  config.include EmailSpecHelper, type: :job

  # Clear deliveries before each test
  config.before(:each) do
    ActionMailer::Base.deliveries.clear
  end
end
