require 'natsort'

class OrganizationsController < ApplicationController
  before_action :set_organization, only: [:show, :destroy, :verify, :disable, :disable_reason_input, :toggle_visibility]

  skip_authorization_check only: [:index, :new]

  def index
    ordering = 'hidden, LOWER(name)'
    @organizations = Organization.accepted_organizations.order(ordering)
    @my_organizations = Organization.taught_organizations(current_user)
    @my_organizations |= Organization.assisted_organizations(current_user)
    @my_organizations |= Organization.participated_organizations(current_user)
    @my_organizations.natsort_by!(&:name)
  end

  def show
    add_organization_breadcrumb
    ordering = 'hidden, disabled_status, LOWER(courses.name)'
    @my_courses = Course.participated_courses(current_user, @organization).order(ordering).select { |c| c.visible_to?(current_user) }
    @my_assisted_courses = Course.assisted_courses(current_user, @organization).order(ordering).select { |c| c.visible_to?(current_user) }
    @ongoing_courses = @organization.courses.ongoing.order(ordering).select { |c| c.visible_to?(current_user) }
    @expired_courses = @organization.courses.expired.order(ordering).select { |c| c.visible_to?(current_user) }
    @my_courses_percent_completed = percent_completed_hash(@my_courses, current_user)
    authorize! :read, @ongoing_courses
    authorize! :read, @expired_courses
  end

  def new
    redirect_to new_setup_organization_path
  end

  def list_requests
    authorize! :view, :unverified_organizations
    add_breadcrumb 'Unverified organizations'
    @unverified_organizations = Organization.pending_organizations
  end

  def verify
    authorize! :verify, :unverified_organizations
    if !@organization.verified
      @organization.verified = true
      @organization.verified_at = DateTime.now
      @organization.save
      redirect_to list_requests_organizations_path, notice: 'Organization is now verified.'
    else
      redirect_to organization_path(@organization)
    end
  end

  def disable_reason_input
    authorize! :disable, Organization
    add_organization_breadcrumb
    add_breadcrumb 'Disable organization'
  end

  def disable
    authorize! :disable, Organization
    if !@organization.disabled
      @organization.disabled = true
      @organization.disabled_reason = organization_params[:disabled_reason]
      @organization.save
      redirect_to list_requests_organizations_path, notice: "Organization #{@organization.name} successfully disabled."
    else
      redirect_to organization_path(@organization)
    end
  end

  def toggle_visibility
    authorize! :toggle_visibility, @organization
    @organization.hidden = !@organization.hidden
    @organization.save!
    redirect_to organization_path, notice: "Organization is now #{@organization.hidden ? 'hidden to users':'visible to users'}"
  end

  private

  def percent_completed_hash(courses, user)
    percent_completed = {}
    awarded_points = Hash[user.awarded_points.to_a.sort!.group_by(&:course_id).map { |k, v| [k, v.map(&:name)] }]
    courses.each do |course|
      if course.visible_to?(current_user)
        awarded = awarded_points[course.id]
        missing = AvailablePoint.course_points(course).order!.map(&:name) - awarded
        if awarded.size + missing.size > 0
          percent_completed[course.id] = 100 * (awarded.size.to_f / (awarded.size + missing.size))
        else
          percent_completed[course.id] = 0
        end
      end
    end
    percent_completed
  end

  def set_organization
    @organization = Organization.find_by(slug: params[:id])
    fail ActiveRecord::RecordNotFound, 'Invalid organization id' if @organization.nil?
  end

  def organization_params
    params.require(:organization).permit(:name, :information, :logo, :slug, :contact_information, :phone, :email, :disabled_reason)
  end
end
