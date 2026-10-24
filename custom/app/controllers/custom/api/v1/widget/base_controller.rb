# frozen_string_literal: true

module Custom::Api::V1::Widget::BaseController
  private

  def conversation_params
    params = super
    attrs = (params[:additional_attributes] || {}).stringify_keys
    attrs[Custom::Conversations::OpenedByStamper::ATTRIBUTE_KEY] ||= Custom::Conversations::OpenedByStamper::CONTACT
    params.merge(additional_attributes: attrs)
  end
end
