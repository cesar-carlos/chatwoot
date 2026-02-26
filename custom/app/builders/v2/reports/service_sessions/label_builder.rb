class V2::Reports::ServiceSessions::LabelBuilder < V2::Reports::ServiceSessions::BaseBuilder
  def build
    labels = account.labels.to_a
    return [] if labels.empty?

    open_counts = open_sessions_by_label
    closed_rows = closed_sessions_by_label
    closed_by_label = closed_rows.index_by(&:first)

    labels.map do |label|
      closed_row = closed_by_label[label.id] || [label.id, 0, nil]

      {
        id: label.id,
        name: label.title,
        open_sessions_count: open_counts[label.id] || 0,
        closed_sessions_count: closed_row[1] || 0,
        avg_session_duration: closed_row[2]&.to_f
      }
    end
  end

  private

  def open_sessions_by_label
    scope = open_sessions_scope(apply_label_filter: false)
            .joins(CONVERSATION_LABEL_JOIN_SQL)
    scope = scope.where(taggings: { tag_id: label_ids }) if label_ids.present?

    scope.group('taggings.tag_id').count
  end

  def closed_sessions_by_label
    scope = closed_sessions_scope(apply_label_filter: false)
            .joins(conversation: :taggings)
            .where(taggings: { taggable_type: 'Conversation', context: 'labels' })
    scope = scope.where(taggings: { tag_id: label_ids }) if label_ids.present?

    scope.group('taggings.tag_id').pluck(
      'taggings.tag_id',
      Arel.sql('COUNT(DISTINCT reporting_events.id)'),
      Arel.sql("AVG(reporting_events.#{metric_column})")
    )
  end
end
