# frozen_string_literal: true

class Custom::Whatsapp::Evolution::ApiError < StandardError
  attr_reader :status, :body

  def initialize(message = nil, status: nil, body: nil)
    super(message)
    @status = status
    @body = body
  end
end
