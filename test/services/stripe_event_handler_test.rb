require "test_helper"

class StripeEventHandlerTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    # Create a Pay::Customer if Pay is available
    @pay_customer = Pay::Customer.create!(owner: @account, processor: "stripe", processor_id: "cus_123")
  end

  test "sets past_due on payment_failed" do
    failed_event = {
      "type" => "invoice.payment_failed",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "in_1"
        }
      }
    }

    StripeEventHandler.new(event: failed_event).call
    assert @account.reload.settings["past_due"]
  end

  test "clears past_due on payment_succeeded" do
    # First set past_due
    @account.update!(settings: { "past_due" => true })

    succeeded_event = {
      "type" => "invoice.payment_succeeded",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "in_2"
        }
      }
    }

    StripeEventHandler.new(event: succeeded_event).call
    assert_nil @account.reload.settings["past_due"]
  end
end
