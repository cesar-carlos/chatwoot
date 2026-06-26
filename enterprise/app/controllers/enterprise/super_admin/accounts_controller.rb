module Enterprise::SuperAdmin::AccountsController
  def create
    manually_managed = params[:account]&.delete(:manually_managed_features)

    super do |resource|
      if manually_managed.present?
        service = ::Internal::Accounts::InternalAttributesService.new(resource)
        service.manually_managed_features = manually_managed
      end
    end
  end

  def update
    handle_manually_managed_features_before_update

    super
  rescue ActiveRecord::StatementInvalid, PG::NumericValueOutOfRange => e
    handle_account_update_failure(e)
  end

  private

  def handle_manually_managed_features_before_update
    return unless params[:account] && params[:account][:manually_managed_features].present?

    service = ::Internal::Accounts::InternalAttributesService.new(requested_resource)
    service.manually_managed_features = params[:account][:manually_managed_features]
    params[:account].delete(:manually_managed_features)
  end

  def handle_account_update_failure(error)
    ChatwootExceptionTracker.new(error, account: requested_resource).capture_exception
    flash.now[:error] = I18n.t(
      'super_admin.accounts.update.feature_flags_failed',
      default: 'Unable to update account features. Please verify the feature catalog and try again.'
    )
    render :edit, locals: {
      page: Administrate::Page::Form.new(dashboard, requested_resource)
    }, status: :unprocessable_entity
  end
end
