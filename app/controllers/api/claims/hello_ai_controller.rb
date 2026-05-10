# frozen_string_literal: true

require "json"
require "net/http"

module Api
  module Claims
    class HelloAiController < ApplicationController
      include Api::Claims::Concerns::AdminAuthorization

      skip_before_action :authenticate_user!, only: %i[create]
      skip_before_action :require_confirmation, only: %i[create]
      skip_after_action :verify_authorized, only: %i[create]
      skip_forgery_protection only: %i[create]

      # POST /api/claims/admin/hello_ai
      # BODY: { prompt: "hello world" }
      def create
        prompt = params[:prompt].to_s
        raise "Missing prompt" if prompt.strip.empty?

        render json: post_simple_chat(prompt: prompt), status: :ok
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

      def post_simple_chat(prompt:)
        base = ENV["INV_NODE_BASE_URL"].to_s.strip
        raise "Missing ENV INV_NODE_BASE_URL" if base.empty?

        uri = URI("#{base.sub(%r{/\z}, "")}/inv/simple-chat")
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(prompt: prompt)

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
