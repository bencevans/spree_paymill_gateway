require "paymill"

module Spree
  class Gateway::PaymillGateway < Gateway

    OK_RESPONSE = 20000
    DEFAULT_CURRENCY = "GBP"

    preference :private_key, :string
    preference :public_key, :string
    preference :currency, :string, default: "GBP"

    attr_accessible :preferred_private_key, :preferred_public_key, :preferred_currency

    def create_profile(payment)
      paymill_transaction = payment.source
      Rails.logger.info "Creating payment for paymill token: #{paymill_transaction.token_id}"

      begin
        set_payment_key
        paymill_payment = Paymill::Payment.create token: paymill_transaction.token_id
      rescue
        Rails.logger.fatal "Could not create paymill payment: #{$!}"
        raise "Could not create Paymill payment"
      end

      Rails.logger.info "Paymill payment created: #{paymill_payment.id}"
      Rails.logger.debug "Paymill payment: #{paymill_payment.inspect}"
      paymill_transaction.payment_id = paymill_payment.id
      paymill_transaction.payment_response = paymill_payment
      paymill_transaction.save!
    end

    def purchase(money, transaction, options = {})
      payment_id = transaction.payment_id
      Rails.logger.info "Authorising payment for paymill token: #{payment_id}"

      begin
        set_payment_key
        paymill_transaction = Paymill::Transaction.create payment: payment_id,
          amount: money.to_i,
          currency: preferences[:currency],
          description: "Order: #{payment_id}"

        Rails.logger.info "Paymill transaction completed: #{paymill_transaction.id} - #{paymill_transaction.response_code}"
        Rails.logger.debug "Paymill transaction: #{paymill_transaction.inspect}"
        transaction.transaction_id = paymill_transaction.id
        transaction.transaction_response = paymill_transaction
        transaction.save!

        if paymill_transaction.response_code == OK_RESPONSE
          ActiveMerchant::Billing::Response.new(true, 'Paymill Gateway: authorize success', {}, authorization: paymill_transaction.id)
        else
          ActiveMerchant::Billing::Response.new(false, 'Paymill Gateway: authorize failure', { message: "Response Code: #{paymill_transaction.response_code}" })
        end
      rescue
        Rails.logger.info "Paymill transaction failed: #{$!}"
        ActiveMerchant::Billing::Response.new(false, 'Paymill Gateway: complete failure', { message: $! })
      end
    end

    def void(response_code, credit_card, options = {})
      #ActiveMerchant::Billing::Response.new(true, 'Bogus Gateway: Forced success', {}, test: true, authorization: '12345')
    end

    def credit(money, credit_card, response_code, options = {})
      #ActiveMerchant::Billing::Response.new(true, 'Bogus Gateway: Forced success', {}, test: true, authorization: '12345')
    end

    def set_payment_key
      Paymill.api_key = preferences[:private_key]
    end

    def provider_class
      self.class
    end

    def payment_source_class
      Spree::PaymillTransaction
    end

    def actions
      %w(purchase void credit)
    end

    def method_type
      :paymill
    end

    def payment_profiles_supported?
      true
    end

    def auto_capture?
      true
    end

  end
end
