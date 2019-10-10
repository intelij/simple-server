class EmailAuthentications::InvitationsController < Devise::InvitationsController
  helper_method :current_admin

  def new
    authorize current_admin, :new_user_for_invitation?
    super
  end

  def create
    authorize current_admin, :create_user_for_invitation?
    User.transaction do
      super do |resource|
        user = User.new(user_params)
        user.email_authentications = [resource]
        user.save!

        next if permission_params.blank?

        permission_params.each do |attributes|
          user.user_permissions.create!(attributes.permit(
            :permission_slug,
            :resource_id,
            :resource_type))
        end
      end
    end
  end

  protected

  def current_admin
    current_inviter.user
  end

  def pundit_user
    current_admin
  end

  def user_params
    { full_name: params.require(:full_name),
      role: params.require(:role),
      organization_id: params.require(:organization_id),
      device_created_at: Time.now,
      device_updated_at: Time.now,
      sync_approval_status: :denied }
  end

  def permission_params
    params[:permissions]
  end

  def invite_params
    { email: params.require(:email) }
  end
end