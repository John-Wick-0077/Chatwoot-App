module Featurable
  extend ActiveSupport::Concern

  FEATURE_LIST = YAML.safe_load(Rails.root.join('config/features.yml').read).freeze

  included do
    before_create :enable_default_features
  end

  def enable_features(*names)
    self.feature_flags ||= {}
    names.each do |name|
      feature_flags[name.to_s] = true
    end
  end

  def enable_features!(*names)
    enable_features(*names)
    save!
  end

  def disable_features(*names)
    self.feature_flags ||= {}
    names.each do |name|
      feature_flags[name.to_s] = false
    end
  end

  def disable_features!(*names)
    disable_features(*names)
    save!
  end

  def feature_enabled?(name)
    return false if feature_flags.blank?

    feature_flags[name.to_s] == true
  end

  def all_features
    FEATURE_LIST.pluck('name').index_with do |feature_name|
      feature_enabled?(feature_name)
    end
  end

  def enabled_features
    all_features.select { |_feature, enabled| enabled == true }
  end

  def disabled_features
    all_features.select { |_feature, enabled| enabled == false }
  end

  private

  def enable_default_features
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return true if config.blank?

    features_to_enabled = config.value.select { |f| f[:enabled] }.pluck(:name)
    enable_features(*features_to_enabled)
  end
end
