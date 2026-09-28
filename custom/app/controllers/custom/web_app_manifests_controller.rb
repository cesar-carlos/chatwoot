class Custom::WebAppManifestsController < PublicController
  def show
    expires_in 5.minutes, public: true
    render json: Custom::WebAppManifestBuilder.new.perform, content_type: 'application/manifest+json'
  end
end
