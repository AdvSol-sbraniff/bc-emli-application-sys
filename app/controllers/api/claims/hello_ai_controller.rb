# frozen_string_literal: true

require "json"
require "net/http"

module Api
  module Claims
    class HelloAiController < ApplicationController
      include Api::Claims::Concerns::AdminAuthorization
      claims_function "claims.test_tools"

      skip_before_action :authenticate_user!, only: %i[show create]
      skip_before_action :require_confirmation, only: %i[show create]
      skip_after_action :verify_authorized, only: %i[show create]
      skip_forgery_protection only: %i[create]

      def show
        render json: {
                 deployment_name:
                   ::Claims::Genai::DeploymentConfig.current[
                     :comparison_deployment_name
                   ]
               }
      end

      # POST /api/claims/admin/hello_ai
      # BODY: { prompt: "hello world", deployment_name: "my-deployment" }
      def create
        prompt = params[:prompt].to_s
        raise "Missing prompt" if prompt.strip.empty?
        deployment_name = params[:deployment_name].to_s.strip
        raise "Enter a model deployment name" if deployment_name.empty?
        if deployment_name.length > 200
          raise "Model deployment name must be at most 200 characters"
        end

        render json:
                 post_simple_chat(
                   prompt: prompt,
                   deployment_name: deployment_name
                 ),
               status: :ok
      rescue => e
        Rails.logger.error(
          "[claims][hello_ai][create] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 ok: false,
                 error: e.message
               },
               status: :unprocessable_entity
      end

      private

      def post_simple_chat(prompt:, deployment_name:)
        base = ENV["INV_NODE_BASE_URL"].to_s.strip
        raise "Missing ENV INV_NODE_BASE_URL" if base.empty?

        uri = URI("#{base.sub(%r{/\z}, "")}/inv/simple-chat")
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req.body =
          JSON.generate(prompt: prompt, deployment_name: deployment_name)

        res =
          Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: (uri.scheme == "https"),
            open_timeout: 10,
            read_timeout: 120
          ) { |http| http.request(req) }

        body = res.body.to_s
        unless res.is_a?(Net::HTTPSuccess)
          raise "Simple chat failed HTTP=#{res.code} body=#{body.to_s[0, 1000]}"
        end

        JSON.parse(body)
      end
    end
  end
end
