class SuperAdmin::AccountsController < SuperAdmin::ApplicationController
  # Overwrite any of the RESTful controller actions to implement custom behavior
  # For example, you may want to send an email after a foo is updated.
  #
  # def update
  #   super
  #   send_foo_updated_email(requested_resource)
  # end

  # Override this method to specify custom lookup behavior.
  # This will be used to set the resource for the `show`, `edit`, and `update`
  # actions.
  #
  # def find_resource(param)
  #   Foo.find_by!(slug: param)
  # end

  # The result of this lookup will be available as `requested_resource`

  # Override this if you have certain roles that require a subset
  # this will be used to set the records shown on the `index` action.
  #
  # def scoped_resource
  #   if current_user.super_admin?
  #     resource_class
  #   else
  #     resource_class.with_less_stuff
  #   end
  # end

  # Override `resource_params` if you want to transform the submitted
  # data before it's persisted. For example, the following would turn all
  # empty values into nil values. It uses other APIs such as `resource_class`
  # and `dashboard`:
  #
  def resource_params
    Rails.logger.info "=== RAW PARAMS === #{params.to_unsafe_h.except(:authenticity_token).inspect}"

    permitted_params = super
    Rails.logger.info "=== AFTER super === #{permitted_params.inspect}"

    if permitted_params[:limits].is_a?(ActionController::Parameters)
      permitted_params[:limits] = permitted_params[:limits].permit!.to_h.compact
    elsif permitted_params[:limits].is_a?(Hash)
      permitted_params[:limits] = permitted_params[:limits].compact
    end

    ff_params = params.dig(:account, :feature_flags)
    if ff_params.is_a?(ActionController::Parameters)
      permitted_params[:feature_flags] = ff_params.permit!.to_h
      Rails.logger.info "=== USING NEW feature_flags HASH === #{permitted_params[:feature_flags].inspect}"
    elsif ff_params.is_a?(Hash)
      permitted_params[:feature_flags] = ff_params
      Rails.logger.info "=== USING NEW feature_flags HASH (plain) === #{permitted_params[:feature_flags].inspect}"
    end

    if params[:enabled_features].present?
      enabled_keys = params[:enabled_features].keys.map(&:to_s)
      names = Featurable::FEATURE_LIST.pluck('name')
      permitted_params[:feature_flags] = names.index_with do |name|
        enabled_keys.include?("feature_#{name}")
      end
      Rails.logger.info "=== DERIVED FROM enabled_features === #{permitted_params[:feature_flags].inspect}"
    end

    if params[:enabled_features].present?
      enabled_keys = params[:enabled_features].keys.map(&:to_s)
      names = Featurable::FEATURE_LIST.pluck('name') # ["agent_bots", "automations", ...]
      permitted_params[:feature_flags] = names.index_with do |name|
        enabled_keys.include?("feature_#{name}")
      end
      Rails.logger.info "=== DERIVED FROM enabled_features === #{permitted_params[:feature_flags].inspect}"
    end

    if params[:selected_feature_flags].present?
      selected = Array(params[:selected_feature_flags]).map { |s| s.to_s.sub(/^feature_/, '') }
      names = Featurable::FEATURE_LIST.pluck('name')
      permitted_params[:feature_flags] ||= {}
      names.each { |name| permitted_params[:feature_flags][name] = selected.include?(name) }
      Rails.logger.info "=== DERIVED FROM selected_feature_flags === #{permitted_params[:feature_flags].inspect}"
    end
    permitted_params[:feature_flags] ||= {}

    final_attrs = permitted_params.permit!.to_h
    Rails.logger.info "=== FINAL PARAMS TO UPDATE === #{permitted_params.inspect}"
    final_attrs
  end

  # See https://administrate-prototype.herokuapp.com/customizing_controller_actions
  # for more information

  def seed
    Internal::SeedAccountJob.perform_later(requested_resource)
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_back(fallback_location: [namespace, requested_resource], notice: 'Account seeding triggered')
    # rubocop:enable Rails/I18nLocaleTexts
  end

  def reset_cache
    requested_resource.reset_cache_keys
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_back(fallback_location: [namespace, requested_resource], notice: 'Cache keys cleared')
    # rubocop:enable Rails/I18nLocaleTexts
  end

  def destroy
    account = Account.find(params[:id])

    DeleteObjectJob.perform_later(account) if account.present?
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_back(fallback_location: [namespace, requested_resource], notice: 'Account deletion is in progress.')
    # rubocop:enable Rails/I18nLocaleTexts
  end
end

SuperAdmin::AccountsController.prepend_mod_with('SuperAdmin::AccountsController')
