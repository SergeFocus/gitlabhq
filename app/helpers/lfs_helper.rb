module LfsHelper
  include Gitlab::Routing.url_helpers

  def require_lfs_enabled!
    return if Gitlab.config.lfs.enabled

    render(
      json: {
        message: 'Git LFS is not enabled on this GitLab server, contact your admin.',
        documentation_url: help_url,
      },
      status: 501
    )
  end

  def lfs_check_access!
    return if download_request? && lfs_download_access?
    return if upload_request? && lfs_upload_access?

    if project.public? || (user && user.can?(:read_project, project))
      if project.above_size_limit? || objects_exceed_repo_limit?
        render_size_error
      else
        render_lfs_forbidden
      end
    else
      render_lfs_not_found
    end
  end

  def lfs_download_access?
    return false unless project.lfs_enabled?

    project.public? || ci? || lfs_deploy_token? || user_can_download_code? || build_can_download_code?
  end

  def user_can_download_code?
    has_authentication_ability?(:download_code) && can?(user, :download_code, project)
  end

  def build_can_download_code?
    has_authentication_ability?(:build_download_code) && can?(user, :build_download_code, project)
  end

  def lfs_upload_access?
    return false unless project.lfs_enabled?
    return false if project.above_size_limit? || objects_exceed_repo_limit?

    has_authentication_ability?(:push_code) && can?(user, :push_code, project)
  end

  def objects_exceed_repo_limit?
    return false unless project.size_limit_enabled?
    return @limit_exceeded if defined?(@limit_exceeded)

    size_of_objects = objects.sum { |o| o[:size] }

    @limit_exceeded = (project.repository_and_lfs_size + size_of_objects.to_mb) > project.actual_size_limit
  end

  def render_lfs_forbidden
    render(
      json: {
        message: 'Access forbidden. Check your access level.',
        documentation_url: help_url,
      },
      content_type: "application/vnd.git-lfs+json",
      status: 403
    )
  end

  def render_lfs_not_found
    render(
      json: {
        message: 'Not found.',
        documentation_url: help_url,
      },
      content_type: "application/vnd.git-lfs+json",
      status: 404
    )
  end

  def render_size_error
    render(
      json: {
        message: Gitlab::RepositorySizeError.new(project).push_error,
        documentation_url: help_url,
      },
      content_type: "application/vnd.git-lfs+json",
      status: 406
    )
  end

  def storage_project
    @storage_project ||= begin
      result = project

      loop do
        break unless result.forked?
        result = result.forked_from_project
      end

      result
    end
  end
end
