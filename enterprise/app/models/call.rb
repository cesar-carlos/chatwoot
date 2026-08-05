# == Schema Information
#
# Table name: calls
#
#  id                   :bigint           not null, primary key
#  direction            :integer          not null
#  duration_seconds     :integer
#  end_reason           :string
#  meta                 :jsonb
#  provider             :integer          default("twilio"), not null
#  started_at           :datetime
#  status               :string           default("ringing"), not null
#  transcript           :text
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  accepted_by_agent_id :bigint
#  account_id           :bigint           not null
#  contact_id           :bigint           not null
#  conversation_id      :bigint           not null
#  inbox_id             :bigint           not null
#  message_id           :bigint
#  provider_call_id     :string           not null
#
# Indexes
#
#  index_calls_on_account_id_and_contact_id       (account_id,contact_id)
#  index_calls_on_account_id_and_conversation_id  (account_id,conversation_id)
#  index_calls_on_account_id_and_created_at       (account_id,created_at)
#  index_calls_on_message_id                      (message_id)
#  index_calls_on_provider_and_provider_call_id   (provider,provider_call_id) UNIQUE
#
class Call < ApplicationRecord
  STATUSES = %w[ringing in_progress completed no_answer failed rejected].freeze
  TERMINAL_STATUSES = %w[completed no_answer failed rejected].freeze

  store_accessor :meta, :conference_sid, :twilio_conference_sid, :recording_sid, :parent_call_sid, :initiated_at, :ended_at

  # Frontend voice bubbles/stores expect inbound/outbound string values
  DISPLAY_DIRECTION = { 'incoming' => 'inbound', 'outgoing' => 'outbound' }.freeze

  DEFAULT_STUN_URL = 'stun:stun.l.google.com:19302'.freeze

  # FORK: persist Wavoip voice calls in the shared call timeline
  enum :provider, { twilio: 0, whatsapp: 1, wavoip: 2 }
  enum :direction, { incoming: 0, outgoing: 1 }

  belongs_to :account
  belongs_to :inbox
  belongs_to :conversation
  belongs_to :contact
  belongs_to :message, optional: true, inverse_of: :call
  belongs_to :accepted_by_agent, class_name: 'User', optional: true

  has_one_attached :recording

  validates :provider_call_id, presence: true
  validates :provider, presence: true
  validates :direction, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :active, -> { where.not(status: TERMINAL_STATUSES) }
  scope :by_conference_sid, ->(sid) { where("meta->>'conference_sid' = ?", sid) }
  scope :by_twilio_conference_sid, ->(sid) { where("meta->>'twilio_conference_sid' = ?", sid) }

  def self.find_by_provider_call_id(provider, sid)
    find_by(provider: provider, provider_call_id: sid)
  end

  def default_conference_sid
    "conf_account_#{account_id}_call_#{id}"
  end

  # FORK: ICE/TURN servers from GlobalConfigService (VOICE_CALL_ICE_SERVERS / VOICE_CALL_STUN_URLS)
  # Browser ↔ Meta WebRTC needs STUN/TURN servers to discover srflx/relay candidates.
  def self.default_ice_servers
    raw = GlobalConfigService.load('VOICE_CALL_ICE_SERVERS', nil)
    return parse_ice_servers(raw) if raw.present?

    stun_raw = GlobalConfigService.load('VOICE_CALL_STUN_URLS', DEFAULT_STUN_URL)
    urls = stun_raw.to_s.split(',').filter_map { |u| u.strip.presence }
    [{ urls: urls }]
  end

  def self.parse_ice_servers(raw)
    parsed = raw.is_a?(String) ? JSON.parse(raw) : raw
    Array(parsed).filter_map { |entry| build_ice_server_entry(entry) }.presence || [{ urls: DEFAULT_STUN_URL }]
  rescue JSON::ParserError
    [{ urls: DEFAULT_STUN_URL }]
  end

  def self.build_ice_server_entry(entry)
    entry = entry.with_indifferent_access
    urls = entry[:urls]
    return if urls.blank?

    server = { urls: urls }
    server[:username] = entry[:username] if entry[:username].present?
    server[:credential] = entry[:credential] if entry[:credential].present?
    server
  end

  def direction_label
    DISPLAY_DIRECTION[direction]
  end

  # Normalize filter values back to stored forms so API/dashboard clients can
  # query using either the display value (inbound/outbound, in-progress) or the
  # stored value (incoming/outgoing, in_progress).
  def self.direction_from_label(value)
    DISPLAY_DIRECTION.key(value) || value
  end

  def self.status_from_display(value)
    value.to_s.tr('-', '_')
  end

  def ringing?
    status == 'ringing'
  end

  def in_progress?
    status == 'in_progress'
  end

  def terminal?
    TERMINAL_STATUSES.include?(status)
  end

  def display_status
    status.to_s.tr('_', '-')
  end

  def from_number
    incoming? ? contact.phone_number : inbox.channel&.phone_number
  end

  def to_number
    incoming? ? inbox.channel&.phone_number : contact.phone_number
  end

  def recording_url
    return nil unless recording.attached?

    Rails.application.routes.url_helpers.rails_blob_url(recording)
  end

  def push_event_data
    {
      id: id,
      provider_call_id: provider_call_id,
      provider: provider,
      direction: direction,
      status: display_status,
      duration_seconds: duration_seconds,
      end_reason: end_reason,
      conference_sid: conference_sid,
      accepted_by_agent_id: accepted_by_agent_id,
      accepted_by_agent_name: accepted_by_agent&.available_name,
      started_at: started_at&.to_i,
      ended_at: ended_at,
      from_number: from_number,
      to_number: to_number,
      recording_url: recording_url,
      transcript: transcript
    }
  end
end

# FORK: wavoip recording_url fallback from meta when attachment missing
Call.prepend_mod_with('Call')
