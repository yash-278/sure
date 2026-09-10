module Settings::AiFeaturesHelper
  def ai_feature_status(connections, feature, selection)
    prefix = "settings.ai_features.show"
    return t("#{prefix}.unconfigured") if selection.blank?
    return t("#{prefix}.consent_off") unless Current.user.ai_enabled?
    connection = connections.find { |item| item[:id] == selection["connection"] }
    return t("#{prefix}.states.#{connection.dig(:status, :state)}") unless connection.dig(:status, :state) == "connected"
    model = connection[:models].find { |item| item["id"] == selection["model"] }
    return t("#{prefix}.model_unavailable") unless model
    Ai::Features.new(Current.user).validate!(feature, selection, model)
    t("#{prefix}.configured")
  rescue Provider::Error
    t("#{prefix}.incompatible")
  end

  def ai_model_options(connections, feature, selection)
    selected = selection["model"].present? ? "#{selection['connection']}:#{selection['model']}" : ""
    groups = connections.map do |connection|
      options = connection[:models].map do |model|
        reason = if model["verified"] == false
          t("settings.ai_features.show.verification_required")
        elsif feature.in?(%w[pdf_summary statement_extraction]) && !model["images"]
          t("settings.ai_features.show.image_required")
        end
        label = "#{model['name']} · #{connection[:name]}"
        label += " · #{reason}" if reason
        [ label, "#{connection[:id]}:#{model['id']}", { disabled: reason.present? } ]
      end
      [ connection[:name], options ]
    end
    if selected.present? && groups.none? { |_, models| models.any? { |_, value, _| value == selected } }
      groups << [ t("settings.ai_features.show.saved_selection"), [ [ t("settings.ai_features.show.unavailable_selection", model: selection["model"]), selected ] ] ]
    end
    options_for_select([ [ t("settings.ai_features.show.choose"), "" ] ], selected) + grouped_options_for_select(groups, selected)
  end
end
