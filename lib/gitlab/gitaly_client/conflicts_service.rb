module Gitlab
  module GitalyClient
    class ConflictsService
      include Gitlab::EncodingHelper

      MAX_MSG_SIZE = 128.kilobytes.freeze

      def initialize(repository, our_commit_oid, their_commit_oid)
        @gitaly_repo = repository.gitaly_repository
        @repository = repository
        @our_commit_oid = our_commit_oid
        @their_commit_oid = their_commit_oid
      end

      def list_conflict_files
        request = Gitaly::ListConflictFilesRequest.new(
          repository: @gitaly_repo,
          our_commit_oid: @our_commit_oid,
          their_commit_oid: @their_commit_oid
        )
        response = GitalyClient.call(@repository.storage, :conflicts_service, :list_conflict_files, request)

        files_from_response(response).to_a
      end

      def resolve_conflicts(target_repository, resolution, source_branch, target_branch)
        reader = binary_stringio(resolution.files.to_json)

        req_enum = Enumerator.new do |y|
          header = resolve_conflicts_request_header(target_repository, resolution, source_branch, target_branch)
          y.yield Gitaly::ResolveConflictsRequest.new(header: header)

          until reader.eof?
            chunk = reader.read(MAX_MSG_SIZE)

            y.yield Gitaly::ResolveConflictsRequest.new(files_json: chunk)
          end
        end

        response = GitalyClient.call(@repository.storage, :conflicts_service, :resolve_conflicts, req_enum, remote_storage: target_repository.storage)

        if response.resolution_error.present?
          raise Gitlab::Git::Conflict::Resolver::ResolutionError, response.resolution_error
        end
      end

      private

      def resolve_conflicts_request_header(target_repository, resolution, source_branch, target_branch)
        Gitaly::ResolveConflictsRequestHeader.new(
          repository: @gitaly_repo,
          our_commit_oid: @our_commit_oid,
          target_repository: target_repository.gitaly_repository,
          their_commit_oid: @their_commit_oid,
          source_branch: source_branch,
          target_branch: target_branch,
          commit_message: resolution.commit_message,
          user: Gitlab::Git::User.from_gitlab(resolution.user).to_gitaly
        )
      end

      def files_from_response(response)
        files = []

        response.each do |msg|
          msg.files.each do |gitaly_file|
            if gitaly_file.header
              files << file_from_gitaly_header(gitaly_file.header)
            else
              files.last.content << gitaly_file.content
            end
          end
        end

        files
      end

      def file_from_gitaly_header(header)
        Gitlab::Git::Conflict::File.new(
          Gitlab::GitalyClient::Util.git_repository(header.repository),
          header.commit_oid,
          conflict_from_gitaly_file_header(header),
          ''
        )
      end

      def conflict_from_gitaly_file_header(header)
        {
          ours: { path: header.our_path, mode: header.our_mode },
          theirs: { path: header.their_path }
        }
      end
    end
  end
end
