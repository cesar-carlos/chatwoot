json.payload do
  json.array! @messages do |message|
    json.partial! 'api/v1/models/message', message: message
    matched_on = @matched_on_by_id[message.id]
    json.matched_on matched_on if matched_on.present?
  end
end

json.meta do
  json.current_page @current_page
  json.has_more @has_more
  json.max_results Custom::ConversationMessageSearchFinder::MAX_RESULTS
  json.search_engine @search_engine
end
