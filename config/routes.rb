require "sidekiq/web"
require "sidekiq/cron/web"

Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  if Rails.env.production?
    Sidekiq::Web.use Rack::Auth::Basic do |username, password|
      ActiveSupport::SecurityUtils.secure_compare(
        ::Digest::SHA256.hexdigest(username),
        ::Digest::SHA256.hexdigest(ENV["SIDEKIQ_USERNAME"])
      ) &
        ActiveSupport::SecurityUtils.secure_compare(
          ::Digest::SHA256.hexdigest(password),
          ::Digest::SHA256.hexdigest(ENV["SIDEKIQ_PASSWORD"])
        )
    end
  end

  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  mount Sidekiq::Web => "/sidekiq"
  mount Rswag::Ui::Engine => "/integrations/api_docs"
  mount Rswag::Api::Engine => "/integrations/api_docs"
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", :as => :rails_health_check

  scope module: :api, path: :api do
    devise_for :users,
               defaults: {
                 format: :json
               },
               path: "",
               path_names: {
                 sign_in: "login",
                 sign_out: "logout"
               },
               controllers: {
                 sessions: "api/sessions",
                 invitations: "api/invitations",
                 omniauth_callbacks: "api/omniauth_callbacks"
               }

    devise_scope :user do
      get "/validate_token" => "sessions#validate_token"
      get "/websocket_token" => "sessions#websocket_token"
      delete "/invitation/remove" => "invitations#remove"
      get "/invitations/:invitation_token" => "invitations#show"
      get "/logout" => "sessions#destroy"
    end

    get "/permit_type_submission_contacts/confirm",
        to: "permit_type_submission_contacts#confirm",
        as: :permit_type_submission_contact_confirmation

    # sbra20260130 claims subsystem (stable bookmark = invoice_id)
    scope module: :claims, path: "claims" do
      get "contractor/invoices", to: "contractor_portal#index"
      post "contractor/invoices/upload_batch",
           to: "contractor_portal#upload_batch"
      get "contractor/invoices/:invoice_id/revision_requests",
          to: "contractor_portal#revision_requests"
      post "contractor/invoices/:invoice_id/revision_requests",
           to: "contractor_portal#create_revision_request"
      patch "contractor/invoices/:invoice_id/revision_requests/:id",
            to: "contractor_portal#update_revision_request"
      post "contractor/invoices/:invoice_id/submit_to_admin",
           to: "contractor_portal#submit_to_admin"
      get "contractor/ingest/runs/:ingest_run_id",
          to: "contractor_portal#ingest_run_show"
      get "contractor/ingest/runs/:ingest_run_id/invoices",
          to: "contractor_portal#ingest_run_invoices"
      get "contractor/ingest/invoices/:invoice_id/steps",
          to: "contractor_portal#ingest_invoice_steps"

      # ============================================================
      # SECTION 10 — READ / NAV (existing)
      # ============================================================

      # Nav bar list for a session (returns invoice_ids in display order)
      get "sessions/:session_id/current_invoices",
          to: "invoice_versions#current_invoices"

      # Read-screen payload for one invoice (resolves to *current* invoice_version)
      get "sessions/:session_id/invoices/:invoice_id/read",
          to: "invoice_versions#read"

      # GenAI located fields for the *current* invoice_version of an invoice
      get "sessions/:session_id/invoices/:invoice_id/read_genai",
          to: "invoice_versions#read_genai"

      get "sessions/:session_id/invoices/:invoice_id/pdf_url",
          to: "invoice_versions#pdf_url"
      get "sessions/:session_id/invoices/:invoice_id/pdf",
          to: "invoice_versions#pdf"
      get "sessions/:session_id/invoices/:invoice_id/supporting_documents/:id/pdf_url",
          to: "invoice_versions#supporting_document_pdf_url"

      # ============================================================
      # SECTION 12 — ADMIN GRID (POC)
      # ============================================================
      get "sessions/:session_id/invoices", to: "invoices#index_by_session"

      get "admin/invoices", to: "invoice_grid#index"

      delete "admin/invoices/:id", to: "invoice_grid#destroy"
      post "admin/invoices/:id/status_transition",
           to: "invoice_grid#status_transition"
      post "admin/invoices/:id/reanalyze_advice",
           to: "invoice_grid#reanalyze_advice"
      get "admin/invoices/:invoice_id/supporting_documents/context",
          to: "invoice_supporting_documents#context"
      get "admin/invoices/:invoice_id/supporting_documents",
          to: "invoice_supporting_documents#index"
      delete "admin/supporting_documents/:id",
             to: "invoice_supporting_documents#destroy"
      get "admin/supporting_documents/:id/pdf_url",
          to: "invoice_supporting_documents#pdf_url"
      get "admin/supporting_documents/:id/pdf",
          to: "invoice_supporting_documents#pdf"
      get "admin/reports/volume_value/summary",
          to: "reports_volume_value#summary"
      get "admin/reports/volume_value/trend", to: "reports_volume_value#trend"
      get "admin/reports/volume_value/detail", to: "reports_volume_value#detail"

      # ============================================================
      # SECTION 20 — SESSION CRUD (AI Admin / POC)
      # ============================================================

      # Create new session (AI Admin screen)
      post "sessions", to: "sessions#create"

      # ============================================================
      # SECTION 30 — INGEST (AI Admin / POC)
      # ============================================================

      post "invoices/:invoice_id/upload_fix_package",
           to: "ingest#upload_fix_package"

      # ============================================================
      # SECTION 40 — RUN TRACKER (AI Admin / POC)
      # ============================================================

      # List ingest runs (optionally filter by session_id)
      get "ingest/runs", to: "ingest#runs_index"
      get "ingest/runs/:ingest_run_id", to: "ingest#run_show"
      get "ingest/runs/:ingest_run_id/steps", to: "ingest#steps_index"
      get "ingest/runs/:ingest_run_id/invoices", to: "ingest#run_invoices_index"
      get "ingest/steps", to: "ingest#steps_by_session_index"
      get "ingest/invoices/:invoice_id/steps",
          to: "ingest#steps_by_invoice_index"

      post "ingest/admin_submit_batch", to: "ingest#admin_submit_batch"

      post "ingest/run_ocr", to: "ingest#run_ocr"

      # ============================================================
      # SECTION 50 — ADMIN / POC (claims)
      # ============================================================

      # Screen B: list ALL invoice_versions for an invoice_id (grid)
      get "admin/invoices/:invoice_id/invoice_versions",
          to: "invoice_versions_admin#index_by_invoice"
      get "admin/invoices/:invoice_id/current_version/read",
          to: "invoice_versions_admin#read_current_by_invoice"
      get "admin/invoices/:invoice_id/current_version/read_genai",
          to: "invoice_versions_admin#read_genai_current_by_invoice"
      get "admin/invoices/:invoice_id/current_version/pdf_url",
          to: "invoice_versions_admin#pdf_url_current_by_invoice"
      get "admin/invoices/:invoice_id/current_version/pdf",
          to: "invoice_versions_admin#pdf_current_by_invoice"

      # Screen B: fetch raw JSON blobs for one invoice_version (tabs)
      get "admin/invoice_versions/:id", to: "invoice_versions_admin#show"
      get "admin/invoice_versions/:id/read",
          to: "invoice_versions_admin#read_by_version"
      get "admin/invoice_versions/:id/read_genai",
          to: "invoice_versions_admin#read_genai_by_version"
      get "admin/invoice_versions/:id/pdf_url",
          to: "invoice_versions_admin#pdf_url_by_version"
      get "admin/invoice_versions/:id/pdf",
          to: "invoice_versions_admin#pdf_by_version"

      # ============================================================
      # SECTION 60 — RULESET EDITOR (admin)
      # ============================================================

      get "admin/ahri_products", to: "ahri_products_admin#index"
      get "admin/ahri_products/import_status",
          to: "ahri_products_admin#import_status"
      post "admin/ahri_products/import_downloaded_pdf",
           to: "ahri_products_admin#import_downloaded_pdf"
      get "admin/neea_products", to: "neea_products_admin#index"
      get "admin/neea_products/import_status",
          to: "neea_products_admin#import_status"
      post "admin/neea_products/import_downloaded_pdf",
           to: "neea_products_admin#import_downloaded_pdf"
      get "admin/awhp_products", to: "awhp_products_admin#index"
      get "admin/awhp_products/import_status",
          to: "awhp_products_admin#import_status"
      post "admin/awhp_products/import_downloaded_pdf",
           to: "awhp_products_admin#import_downloaded_pdf"
      get "admin/ohpa_products", to: "ohpa_products_admin#index"
      get "admin/ohpa_products/import_status",
          to: "ohpa_products_admin#import_status"
      post "admin/ohpa_products/import_downloaded_csv",
           to: "ohpa_products_admin#import_downloaded_csv"
      get "admin/validation_rules", to: "validation_rules_admin#index"
      get "admin/validation_rules/upgrade_types",
          to: "validation_rules_admin#upgrade_types"
      get "admin/validationgenai_config", to: "validationgenai_config#show"
      patch "admin/validationgenai_config", to: "validationgenai_config#update"
      get "admin/supporting_document_types",
          to: "supporting_document_types_admin#index"
      get "admin/supporting_document_types/:id",
          to: "supporting_document_types_admin#show"
      post "admin/supporting_document_types",
           to: "supporting_document_types_admin#create"
      patch "admin/supporting_document_types/:id",
            to: "supporting_document_types_admin#update"
      get "admin/supporting_document_types/:supporting_document_type_id/located_fields",
          to: "supporting_document_type_located_fields_admin#index"
      post "admin/supporting_document_types/:supporting_document_type_id/located_fields",
           to: "supporting_document_type_located_fields_admin#create"
      get "admin/supporting_document_type_located_fields/:id",
          to: "supporting_document_type_located_fields_admin#show"
      patch "admin/supporting_document_type_located_fields/:id",
            to: "supporting_document_type_located_fields_admin#update"
      get "admin/validation_rules/:record_type/:id/history",
          to: "validation_rules_admin#history"
      post "admin/validation_rules/:record_type",
           to: "validation_rules_admin#create"
      patch "admin/validation_rules/:record_type/:id",
            to: "validation_rules_admin#update"

      get "admin/contractors", to: "contractors_admin#index"
      get "admin/contractors/:id", to: "contractors_admin#show"
      post "admin/contractors", to: "contractors_admin#create"
      patch "admin/contractors/:id", to: "contractors_admin#update"
      delete "admin/contractors/:id", to: "contractors_admin#destroy"
      post "admin/hello_ai", to: "hello_ai#create"

      get "admin/sessions/:id", to: "sessions_admin#show"
      patch "admin/sessions/:id", to: "sessions_admin#update"
      get "admin/sessions_with_contractors",
          to: "sessions_with_contractors_admin#index"
      delete "admin/sessions_with_contractors/:id",
             to: "sessions_with_contractors_admin#destroy"
      get "admin/users", to: "users_admin#index"
      get "admin/users/:id", to: "users_admin#show"
      post "admin/users", to: "users_admin#create"
      patch "admin/users/:id", to: "users_admin#update"
      delete "admin/users/:id", to: "users_admin#destroy"
      get "admin/user_eligibilitycodes", to: "user_eligibilitycodes_admin#index"
      get "admin/users_eligibilitycodes/:id",
          to: "user_eligibilitycodes_admin#show"
      post "admin/users_eligibilitycodes",
           to: "user_eligibilitycodes_admin#create"
      patch "admin/users_eligibilitycodes/:id",
            to: "user_eligibilitycodes_admin#update"
      get "admin/revision_requests", to: "revision_requests_admin#index"
      get "admin/revision_requests/:id", to: "revision_requests_admin#show"
      post "admin/revision_requests", to: "revision_requests_admin#create"
      patch "admin/revision_requests/:id", to: "revision_requests_admin#update"
      delete "admin/revision_requests/:id",
             to: "revision_requests_admin#destroy"
      get "admin/internal_notes", to: "internal_notes_admin#index"
      post "admin/internal_notes", to: "internal_notes_admin#create"
    end
    # end sbra

    resources :requirement_blocks, only: %i[create show update destroy] do
      post "restore", on: :member, to: "requirement_blocks#restore"
      post "search", on: :collection, to: "requirement_blocks#index"
      get "auto_compliance_module_configurations",
          on: :collection,
          to: "requirement_blocks#auto_compliance_module_configurations"
    end

    resources :notifications, only: %i[index destroy] do
      post "reset_last_read",
           on: :collection,
           to: "notifications#reset_last_read"
      delete "clear_all", on: :collection, to: "notifications#clear_all"
    end

    resources :requirement_templates, only: %i[show create destroy update] do
      post "search", on: :collection, to: "requirement_templates#index"
      post "schedule", to: "requirement_templates#schedule", on: :member
      post "force_publish_now",
           to: "requirement_templates#force_publish_now",
           on: :member
      post "invite_previewers",
           to: "requirement_templates#invite_previewers",
           on: :member
      patch "restore", on: :member
      post "template_versions/:id/unschedule",
           on: :collection,
           to: "requirement_templates#unschedule_template_version"
      post "copy", on: :collection
    end

    resources :early_access_previews do
      member do
        post :revoke_access
        post :unrevoke_access
        post :extend_access
      end
    end

    resources :template_versions, only: %i[index show] do
      get "compare_requirements",
          to: "template_versions#compare_requirements",
          on: :member
      get "download_requirement_summary_csv",
          to: "template_versions#download_summary_csv",
          on: :member

      member do
        resources :jurisdictions, only: [] do
          get "jurisdiction_template_version_customization",
              to:
                "template_versions#show_jurisdiction_template_version_customization"
          post "jurisdiction_template_version_customization",
               to:
                 "template_versions#create_or_update_jurisdiction_template_version_customization"
          post "jurisdiction_template_version_customization/promote",
               to:
                 "template_versions#promote_jurisdiction_template_version_customization"
          post "copy_jurisdiction_template_version_customization",
               to:
                 "template_versions#copy_jurisdiction_template_version_customization"
          get "download_customization_csv",
              to: "template_versions#download_customization_csv"
          get "download_customization_json",
              to: "template_versions#download_customization_json"
          get "integration_mapping",
              to: "template_versions#show_integration_mapping"
        end
      end
    end

    resources :integration_mappings, only: [:update]

    resources :jurisdictions, only: %i[index update show create] do
      post "search", on: :collection, to: "jurisdictions#index"
      post "users/search", on: :member, to: "jurisdictions#search_users"
      post "permit_applications/search",
           on: :member,
           to: "programs#search_permit_applications"
      patch "update_external_api_enabled",
            on: :member,
            to: "jurisdictions#update_external_api_enabled"
      get "locality_type_options", on: :collection
      get "jurisdiction_options", on: :collection
    end

    resources :programs, only: %i[index update show create] do
      post "search", on: :collection, to: "programs#index"
      post "users/search", on: :member, to: "programs#search_users"
      post "permit_applications/search",
           on: :member,
           to: "programs#search_permit_applications"
      patch "update_external_api_enabled",
            on: :member,
            to: "programs#update_external_api_enabled"
      get "program_options", on: :collection

      resources :invitations, only: %i[create show], controller: "invitations"

      resources :program_classification_memberships, only: %i[create destroy] do
        collection do
          get :membership_exists
          patch :sync
        end
      end
    end

    resources :contacts, only: %i[create update destroy] do
      get "contact_options", on: :collection
    end

    resources :permit_classifications, only: %i[index] do
      post "permit_classification_options", on: :collection
    end

    resources :eligibility_codes, only: %i[show]

    resources :geocoder, only: %i[] do
      get "site_options", on: :collection
      get "pids", on: :collection
      get "jurisdiction", on: :collection
      get "pin", on: :collection
      get "pid_details", on: :collection
    end

    resources :permit_applications, only: %i[create update show destroy] do
      post "generate_missing_pdfs",
           on: :member,
           to: "permit_applications#generate_missing_pdfs"
      post "permit_collaborations",
           on: :member,
           to: "permit_applications#create_permit_collaboration"
      post "application_assignments",
           on: :member,
           to: "permit_applications#assign_user_to_application"
      post "permit_block_status",
           on: :member,
           to: "permit_applications#create_or_update_permit_block_status"
      delete "permit_collaborations/remove_collaborator_collaborations",
             on: :member,
             to: "permit_applications#remove_collaborator_collaborations"
      post "permit_collaborations/invite",
           on: :member,
           to: "permit_applications#invite_new_collaborator"
      post "search", on: :collection, to: "permit_applications#index"
      post "submit", on: :member
      post "mark_as_viewed", on: :member
      post "change_status", on: :member
      post "approve", on: :member, to: "permit_applications#approve"
      post "approve_pending",
           on: :member,
           to: "permit_applications#approve_pending"
      post "approve_paid", on: :member, to: "permit_applications#approve_paid"
      patch "upload_supporting_document", on: :member
      patch "update_version", on: :member
      patch "revision_requests",
            on: :member,
            to: "permit_applications#update_revision_requests"
      post "revision_requests/finalize",
           on: :member,
           to: "permit_applications#finalize_revision_requests"
      post "revision_requests/apply_without_state_change",
           on: :member,
           to:
             "permit_applications#apply_revision_requests_without_state_change"
      post "revision_requests/remove",
           on: :member,
           to: "permit_applications#remove_revision_requests"
      get "download_application_metrics_csv",
          on: :collection,
          to: "permit_applications#download_application_metrics_csv"
    end

    resources :support_requests, only: %i[index show create update destroy] do
      collection { post :request_supporting_files }
    end

    resources :permit_collaborations, only: %i[destroy] do
      post "reinvite", on: :member, to: "permit_collaborations#reinvite"
    end

    patch "profile", to: "users#profile"

    resources :users, only: %i[] do
      get "current_user/license_agreements",
          on: :collection,
          to: "users#license_agreements"
      get "super_admins", on: :collection, to: "users#super_admins"
      get "active_programs", on: :collection, to: "users#active_programs"
    end

    resources :contractors, only: %i[index show create update destroy] do
      get "current_contractor/license_agreements",
          on: :collection,
          to: "contractors#license_agreements"

      get "by-user/:user_id", on: :collection, to: "contractors#by_user"

      post "shim", on: :collection, to: "contractors#shim"

      # Follow program pattern for contractor users
      post "users/search", on: :member, to: "contractors#search_users"

      # Suspend contractor
      post "suspend", on: :member, to: "contractors#suspend"

      # Unsuspend contractor
      post "unsuspend", on: :member, to: "contractors#unsuspend"

      # Deactivate (remove) contractor
      post "deactivate", on: :member, to: "contractors#deactivate"

      resources :employees, controller: "contractor_employees", only: [] do
        collection { post :invite }
        member do
          post :deactivate
          post :reactivate
          post :reinvite
          post :revoke_invite
          post :set_primary_contact
        end
      end
    end

    resources :contractor_onboards, only: %i[create update show]

    resources :contractor_import, only: %i[create] do
      get "validate/:token", on: :collection, to: "contractor_import#validate"
    end

    resources :audit_logs, only: %i[index] do
      get "filter_options", on: :collection
    end

    resources :users, only: %i[destroy update] do
      patch "restore", on: :member
      patch "accept_eula", on: :member
      patch "role", on: :member, to: "users#update_user_role"
      post "search", on: :collection, to: "users#index"
      post "resend_confirmation", on: :member
      post "reinvite", on: :member
      post "accept_invitation", on: :member
    end

    resources :end_user_license_agreement, only: %i[index]

    resources :step_codes, only: %i[index create destroy], shallow: true do
      resources :step_code_checklists, only: %i[index show update]
      get "download_step_code_summary_csv",
          on: :collection,
          to: "step_codes#download_step_code_summary_csv"
    end

    post "tags/search", to: "tags#index", as: :tags_search

    get "storage/s3" => "storage#upload" # use a storage controller instead of shrine mount since we want api authentication before being able to access
    post "storage/s3/virus_scan" => "storage#virus_scan" # Pre-upload virus scanning
    get "storage/s3/download" => "storage#download"
    delete "storage/s3/delete" => "storage#delete"

    if SHRINE_USE_S3
      mount Shrine.uppy_s3_multipart(:cache) => "/storage/s3/multipart"
    end
    resources :site_configuration, only: [] do
      get :show, on: :collection
      put :update, on: :collection
    end

    resources :external_api_keys do
      post "revoke", on: :member
    end

    resources :collaborators, only: %i[] do
      collection do
        resources :collaboratorable, only: %i[] do
          post "search", to: "collaborators#collaborator_search"
        end
      end
    end

    resources :esp_application, only: [:create]

    resources :program_memberships, only: [] do
      member do
        patch :deactivate
        patch :reactivate
      end
    end

    # Virus scan status API
    get "virus_scan_status/:model/:id", to: "virus_scan_status#show"
    post "virus_scan_status/:model/:id/rescan", to: "virus_scan_status#rescan"
    get "virus_scan_status/bulk", to: "virus_scan_status#bulk"
  end

  scope module: :external_api, path: :external_api do
    namespace :v1 do
      post "applications/search", to: "permit_applications#index"
      get "applications/summary", to: "permit_applications#summary"
      get "applications/:id",
          to: "permit_applications#show",
          as: :external_api_application

      resources :versions, as: "template_versions", only: [] do
        get "integration_mapping",
            to: "permit_applications#show_integration_mapping"
        get "schema", to: "template_versions#show"
        collection { get "schema", to: "template_versions#index" }
      end

      # Contractor Invoice API endpoints
      get "invoices", to: "invoices#index"
      get "invoices/summary", to: "invoices#summary"
      get "invoices/:id", to: "invoices#show", as: :external_api_invoice

      # Contractor data API endpoints
      get "contractors", to: "contractors#index"
      get "contractors/:id",
          to: "contractors#show",
          as: :external_api_contractor
    end
  end

  root to: "home#index"

  get "/reset-password" => "home#index", :as => :reset_password
  get "/login" => "home#index", :as => :login
  get "/confirmed" => "home#index", :as => :confirmed
  get "/accept-invitation" => "home#index", :as => :accept_invitation
  get "/*path",
      to: "home#index",
      format: false,
      constraints: ->(req) do
        !req.path.include?("/rails") && !req.path.start_with?("/public")
      end
  post "/store_entry_point", to: "sessions#store_entry_point"
end
