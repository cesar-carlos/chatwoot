module Custom::Api::V1::Accounts::Conversations::MessagesController
  SEARCH_RATE_LIMIT = 30
  SEARCH_RATE_WINDOW = 1.minute

  def search
    return render_search_error('Too many search requests. Please try again shortly.', :too_many_requests) if search_rate_limited?

    query = normalized_query
    return render_search_error('Search query is required') if query.blank?
    return render_search_error('Search query must be between 2 and 200 characters') unless query.length.between?(2, 200)

    page = parsed_page
    return render_search_error('Page must be a positive integer') if page.nil?

    finder = Custom::ConversationMessageSearchFinder.new(
      conversation: @conversation,
      query: query,
      page: page,
      from: search_params[:from]
    )
    @messages = finder.perform
    @has_more = finder.has_more?
    @current_page = page
    @matched_on_by_id = finder.matched_on_by_id
    @search_engine = finder.search_engine
  end

  def destroy
    ActiveRecord::Base.transaction do
      merged_attrs = (message.content_attributes || {}).stringify_keys.merge('deleted' => true)
      message.update!(
        content: I18n.t('conversations.messages.deleted'),
        content_type: :text,
        content_attributes: merged_attrs
      )
      message.attachments.destroy_all
    end
  end

  private

  def normalized_query
    search_params[:q].to_s.strip
  end

  def parsed_page
    page_param = search_params[:page]
    return 1 if page_param.blank?

    page = Integer(page_param)
    page.positive? ? page : nil
  rescue ArgumentError, TypeError
    nil
  end

  def search_params
    params.permit(:q, :page, :from)
  end

  def render_search_error(message, status = :unprocessable_entity)
    render json: { error: message }, status: status
  end

  def search_rate_limited?
    key = "conversation_message_search:#{Current.user.id}:#{@conversation.id}"
    increment_search_count(key) > SEARCH_RATE_LIMIT
  end

  def increment_search_count(key)
    if Rails.cache.respond_to?(:increment)
      count = Rails.cache.increment(key, 1, expires_in: SEARCH_RATE_WINDOW)
      return count if count
    end

    count = Rails.cache.read(key).to_i + 1
    Rails.cache.write(key, count, expires_in: SEARCH_RATE_WINDOW)
    count
  end
end
