require "administrate/base_dashboard"

class AlertNotificationDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsTo,
    alert_rule: Field::BelongsTo,
    error_message: Field::Text,
    failed_at: Field::DateTime,
    notification_type: Field::String,
    payload: Field::String.with_options(searchable: false),
    project: Field::BelongsTo,
    sent_at: Field::DateTime,
    status: Field::String,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    id
    account
    alert_rule
    error_message
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    account
    alert_rule
    error_message
    failed_at
    notification_type
    payload
    project
    sent_at
    status
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    account
    alert_rule
    error_message
    failed_at
    notification_type
    payload
    project
    sent_at
    status
  ].freeze

  # COLLECTION_FILTERS
  # a hash that defines filters that can be used while searching via the search
  # field of the dashboard.
  #
  # For example to add an option to search for open resources by typing "open:"
  # in the search field:
  #
  #   COLLECTION_FILTERS = {
  #     open: ->(resources) { resources.where(open: true) }
  #   }.freeze
  COLLECTION_FILTERS = {}.freeze

  # Overwrite this method to customize how alert notifications are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(alert_notification)
  #   "AlertNotification ##{alert_notification.id}"
  # end
end
