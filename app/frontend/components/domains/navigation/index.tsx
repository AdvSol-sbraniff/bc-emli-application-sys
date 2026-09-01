import { Box, Center } from '@chakra-ui/react';
import { observer } from 'mobx-react-lite';
import React, { Suspense, lazy, useEffect } from 'react';
import { useTranslation } from 'react-i18next';
import { BrowserRouter, Navigate, Route, Routes, useLocation, useNavigate } from 'react-router-dom';
import { useMst } from '../../../setup/root';
import { EFlashMessageStatus } from '../../../types/enums';
import { FlashMessage } from '../../shared/base/flash-message';
import { LoadingScreen } from '../../shared/base/loading-screen';
import { ClaimsAccessProvider, useClaimsAccess } from '../../shared/claims/claims-access';
import { SupportScreen } from '../misc/support-screen';
import { EULAScreen } from '../onboarding/eula';
import { NavBar } from './nav-bar';
import { ProtectedRoute } from './protected-route';
import { AdminPortalLogin } from '../admin/login';
import { ProgramsIndexScreen } from '../programs';
import { ProgramInviteUserScreen } from '../programs/invite-users';
import { RejectApplicationScreen } from '../energy-savings-application/application-rejection-reason';
import { BlankTemplateScreen } from '../requirement-template/screens/blank-template';
import { ContractorLandingScreen } from '../contractor-landing';
import { ContractorManagementScreen } from '../contractor-management';
import { ContractorEmployeeIndexScreen } from '../contractor-management/employees';
import { ContractorProgramResourcesScreen } from '../contractor-management/contractor-program-resources-screen';
import { ContractorDashboardScreen } from '../contractor-dashboard/contractor-dashboard-screen';
import { AiContractorDashboardScreen } from '../ai-contractor-dashboard/ai-contractor-dashboard-screen';
import ContractorUploadInvoicesScreen from '../contractor-upload-invoices';
import { ContractorOnboardingImport } from '../contractor-landing/import';
import { SuspendReasonPage } from '../contractor-management/suspend-reason-page';
import { RemoveReasonPage } from '../contractor-management/remove-reason-page';
import { ContractorSuspendConfirmedScreen } from '../energy-savings-application/successful-action-screens';
import { ContractorUnsuspendConfirmedScreen } from '../energy-savings-application/successful-action-screens';
import { ContractorRemoveConfirmedScreen } from '../energy-savings-application/successful-action-screens';
import { trackPageViewEvent } from '../../../utils/snowplow';

// sbra20260130 addijng url-routes for the claims subsytem (aka new the genai subsystem)
const InvoiceVersionShowScreen = lazy(() =>
  import('../invoice-versions').then((module) => ({ default: module.InvoiceVersionShowScreen })),
);
const ValidationRulesAdminScreen = lazy(() =>
  import('../validation-rules-admin').then((module) => ({ default: module.default })),
);
const ValidationRulesAlphabeticAdminScreen = lazy(() =>
  import('../validation-rules-alphabetic-admin').then((module) => ({ default: module.default })),
);
const ValidationFieldsAlphabeticAdminScreen = lazy(() =>
  import('../validation-fields-alphabetic-admin').then((module) => ({ default: module.default })),
);
const ValidationRulesConfigScreen = lazy(() =>
  import('../ruleset-config-editor').then((module) => ({ default: module.default })),
);
const SupportingDocumentTypesAdminScreen = lazy(() =>
  import('../supporting-document-types-admin').then((module) => ({ default: module.default })),
);
const SupportingDocumentTypeFieldsAdminScreen = lazy(() =>
  import('../supporting-document-type-fields-admin').then((module) => ({ default: module.default })),
);
const HeatPumpProductListAdminScreen = lazy(() =>
  import('../heat-pump-product-list-admin').then((module) => ({ default: module.default })),
);
const HpwhProductListAdminScreen = lazy(() =>
  import('../hpwh-product-list-admin').then((module) => ({ default: module.default })),
);
const AwhpProductListAdminScreen = lazy(() =>
  import('../awhp-product-list-admin').then((module) => ({ default: module.default })),
);
const OhpaProductListAdminScreen = lazy(() =>
  import('../ohpa-product-list-admin').then((module) => ({ default: module.default })),
);
const HervProductListAdminScreen = lazy(() =>
  import('../herv-product-list-admin').then((module) => ({ default: module.default })),
);
const VentFanProductListAdminScreen = lazy(() =>
  import('../vent-fan-product-list-admin').then((module) => ({ default: module.default })),
);
const DownloadsAdminScreen = lazy(() => import('../downloads-admin').then((module) => ({ default: module.default })));
const HelloAiAdminScreen = lazy(() => import('../hello-ai-admin').then((module) => ({ default: module.default })));
const IngestRunsAdminScreen = lazy(() =>
  import('../ingest-runs-admin').then((module) => ({ default: module.default })),
);
const ClaimsRbacAdminScreen = lazy(() =>
  import('../claims-rbac-admin').then((module) => ({ default: module.default })),
);
const TestSuitesScreen = lazy(() => import('../test-harness').then((module) => ({ default: module.TestSuitesScreen })));
const TestSuiteCasesScreen = lazy(() =>
  import('../test-harness').then((module) => ({ default: module.TestSuiteCasesScreen })),
);
const ModelComparisonsScreen = lazy(() =>
  import('../test-harness').then((module) => ({ default: module.ModelComparisonsScreen })),
);
const NewModelComparisonScreen = lazy(() =>
  import('../test-harness').then((module) => ({ default: module.NewModelComparisonScreen })),
);
const ModelComparisonResultsScreen = lazy(() =>
  import('../test-harness').then((module) => ({ default: module.ModelComparisonResultsScreen })),
);
const RuleComparisonsScreen = lazy(() =>
  import('../test-harness').then((module) => ({ default: module.RuleComparisonsScreen })),
);
const NewRuleComparisonScreen = lazy(() =>
  import('../test-harness').then((module) => ({ default: module.NewRuleComparisonScreen })),
);
const RuleComparisonResultsScreen = lazy(() =>
  import('../test-harness').then((module) => ({ default: module.RuleComparisonResultsScreen })),
);
const RegressionRunsScreen = lazy(() =>
  import('../test-harness').then((module) => ({ default: module.RegressionRunsScreen })),
);
const NewRegressionRunScreen = lazy(() =>
  import('../test-harness').then((module) => ({ default: module.NewRegressionRunScreen })),
);
const RegressionRunResultsScreen = lazy(() =>
  import('../test-harness').then((module) => ({ default: module.RegressionRunResultsScreen })),
);

// the invoicesadmin is in ../invoices-admin/
// below is the code for it
const InvoicesAdminScreen = lazy(() =>
  import('../invoices-admin').then((module) => ({ default: module.InvoicesAdminScreen })),
);

// below is the new code for the invoice-versions admin screen
const InvoiceVersionsAdminScreen = lazy(() =>
  import('../invoice-versions-admin').then((module) => ({ default: module.InvoiceVersionsAdminScreen })),
);

const ContractorFixSimulationAdminScreen = lazy(() =>
  import('../contractor-fix-simulation-admin').then((module) => ({ default: module.default })),
);
const AdviceRefreshSimulationAdminScreen = lazy(() =>
  import('../advice-refresh-simulation-admin').then((module) => ({ default: module.default })),
);
const SubmissionSimulatorAdminScreen = lazy(() =>
  import('../submission-simulator-admin').then((module) => ({ default: module.default })),
);
const InvoiceSupportingDocumentsAdminScreen = lazy(() =>
  import('../invoice-supporting-documents-admin').then((module) => ({ default: module.default })),
);
const ContractorInvoiceReviewScreen = lazy(() =>
  import('../contractor-invoice-review').then((module) => ({ default: module.default })),
);
const ContractorFixUploadScreen = lazy(() =>
  import('../contractor-fix-upload').then((module) => ({ default: module.default })),
);
const ContractorInvoiceMessagesScreen = lazy(() =>
  import('../contractor-invoice-messages').then((module) => ({ default: module.default })),
);

const EligibilitycodesAdminScreen = lazy(() =>
  import('../eligibilitycodes-admin').then((module) => ({ default: module.default })),
);
const ContractorsAdminScreen = lazy(() =>
  import('../contractors-admin').then((module) => ({ default: module.default })),
);
const UsersAdminScreen = lazy(() => import('../users-admin').then((module) => ({ default: module.default })));
const UserEditorScreen = lazy(() => import('../user-editor').then((module) => ({ default: module.default })));
const EligibilitycodeEditorScreen = lazy(() =>
  import('../eligibilitycode-editor').then((module) => ({ default: module.default })),
);
const ConversationMessagesAdminScreen = lazy(() =>
  import('../conversation-messages-admin').then((module) => ({ default: module.default })),
);
const ReportsVolumeValueScreen = lazy(() =>
  import('../reports-volume-value').then((module) => ({ default: module.default })),
);

// end sbra20260130

const ExternalApiKeysIndexScreen = lazy(() =>
  import('../external-api-key').then((module) => ({ default: module.ExternalApiKeysIndexScreen })),
);

const AdminInviteScreen = lazy(() =>
  import('../users/admin-invite-screen').then((module) => ({ default: module.AdminInviteScreen })),
);

const AuditLogScreen = lazy(() => import('../audit-log').then((module) => ({ default: module.AuditLogScreen })));

const ExternalApiKeyModalSubRoute = lazy(() =>
  import('../external-api-key/external-api-key-modal-sub-route').then((module) => ({
    default: module.ExternalApiKeyModalSubRoute,
  })),
);

const NotFoundScreen = lazy(() =>
  import('../../shared/base/not-found-screen').then((module) => ({ default: module.NotFoundScreen })),
);

const PermitApplicationPDFViewer = lazy(() =>
  import('../../shared/energy-savings-applications/pdf-content/viewer').then((module) => ({
    default: module.PermitApplicationPDFViewer,
  })),
);

const EmailConfirmedScreen = lazy(() =>
  import('../authentication/email-confirmed-screen').then((module) => ({ default: module.EmailConfirmedScreen })),
);

const EligibilityCheck = lazy(() =>
  import('../eligibility-check').then((module) => ({ default: module.EligibilityCheck })),
);
const LoginScreen = lazy(() =>
  import('../authentication/login-screen').then((module) => ({ default: module.LoginScreen })),
);
const HomeScreen = lazy(() => import('../home').then((module) => ({ default: module.HomeScreen })));
const ConfigurationManagementScreen = lazy(() =>
  import('../home/review-manager/configuration-management-screen').then((module) => ({
    default: module.ConfigurationManagementScreen,
  })),
);
const EnergyStepRequirementsScreen = lazy(() =>
  import('../home/review-manager/configuration-management-screen/energy-step-requirements-screen').then((module) => ({
    default: module.EnergyStepRequirementsScreen,
  })),
);
const SubmissionsInboxSetupScreen = lazy(() =>
  import('../home/review-manager/configuration-management-screen/submissions-inbox-setup-screen').then((module) => ({
    default: module.SubmissionsInboxSetupScreen,
  })),
);

const NewProgramScreen = lazy(() =>
  import('../programs/new-program-screen').then((module) => ({ default: module.NewProgramScreen })),
);

const JurisdictionIndexScreen = lazy(() =>
  import('../jurisdictions/index').then((module) => ({ default: module.JurisdictionIndexScreen })),
);
const JurisdictionScreen = lazy(() =>
  import('../jurisdictions/jurisdiction-screen').then((module) => ({ default: module.JurisdictionScreen })),
);
const LimitedJurisdictionIndexScreen = lazy(() =>
  import('../jurisdictions/limited-jurisdiction-index-screen').then((module) => ({
    default: module.LimitedJurisdictionIndexScreen,
  })),
);
const NewJurisdictionScreen = lazy(() =>
  import('../jurisdictions/new-jurisdiction-screen').then((module) => ({ default: module.NewJurisdictionScreen })),
);
const ProgramSubmissionInboxScreen = lazy(() =>
  import('../programs/submission-inbox/program-submisson-inbox-screen').then((module) => ({
    default: module.ProgramSubmissionInboxScreen,
  })),
);
const JurisdictionUserIndexScreen = lazy(() =>
  import('../jurisdictions/users').then((module) => ({ default: module.JurisdictionUserIndexScreen })),
);
const ProgramUserIndexScreen = lazy(() =>
  import('../programs/users').then((module) => ({ default: module.ProgramUserIndexScreen })),
);
const LandingScreen = lazy(() => import('../landing').then((module) => ({ default: module.LandingScreen })));
const ContactScreen = lazy(() =>
  import('../misc/contact-screen').then((module) => ({ default: module.ContactScreen })),
);
const EnergySavingsApplicationIndexScreen = lazy(() =>
  import('../energy-savings-application').then((module) => ({ default: module.EnergySavingsApplicationIndexScreen })),
);
const EditPermitApplicationScreen = lazy(() =>
  import('../energy-savings-application/edit-energy-savings-application-screen').then((module) => ({
    default: module.EditPermitApplicationScreen,
  })),
);

const NewApplicationScreen = lazy(() =>
  import('../energy-savings-application/new-application').then((module) => ({
    default: module.NewApplicationScreen,
  })),
);
const NewInvoiceScreen = lazy(() =>
  import('../energy-savings-application/new-invoice-screen').then((module) => ({
    default: module.NewInvoiceScreen,
  })),
);
const ReviewPermitApplicationScreen = lazy(() =>
  import('../energy-savings-application/review-permit-application-screen').then((module) => ({
    default: module.ReviewPermitApplicationScreen,
  })),
);
const SuccessfulSubmissionScreen = lazy(() =>
  import('../energy-savings-application/successful-submission').then((module) => ({
    default: module.SuccessfulSubmissionScreen,
  })),
);
const SuccessfulWithdrawalScreen = lazy(() =>
  import('../energy-savings-application/successful-action-screens').then((module) => ({
    default: module.SuccessfulWithdrawalScreen,
  })),
);
const SuccessfulScreenedInScreen = lazy(() =>
  import('../energy-savings-application/successful-action-screens').then((module) => ({
    default: module.SuccessfulScreenedInScreen,
  })),
);
const SuccessfulApprovedPendingScreen = lazy(() =>
  import('../energy-savings-application/successful-action-screens').then((module) => ({
    default: module.SuccessfulApprovedPendingScreen,
  })),
);
const SuccessfulApprovedPaidScreen = lazy(() =>
  import('../energy-savings-application/successful-action-screens').then((module) => ({
    default: module.SuccessfulApprovedPaidScreen,
  })),
);
const SuccessfulIneligibleScreen = lazy(() =>
  import('../energy-savings-application/successful-action-screens').then((module) => ({
    default: module.SuccessfulIneligibleScreen,
  })),
);
const SuccessfulUpdateScreeen = lazy(() =>
  import('../energy-savings-application/successful-action-screens').then((module) => ({
    default: module.SuccessfulUpdateScreen,
  })),
);
const SuccessfulTrainingPendingScreen = lazy(() =>
  import('../energy-savings-application/successful-action-screens').then((module) => ({
    default: module.SuccessfulTrainingPendingScreen,
  })),
);
const SuccessfulOnboardingApprovalScreen = lazy(() =>
  import('../energy-savings-application/successful-action-screens').then((module) => ({
    default: module.SuccessfulOnboardingApprovalScreen,
  })),
);
const NewRequirementTemplateScreen = lazy(() =>
  import('../requirement-template/new-requirement-template-screen').then((module) => ({
    default: module.NewRequirementTemplateScreen,
  })),
);
const EditRequirementTemplateScreen = lazy(() =>
  import('../requirement-template/screens/edit-requirement-template-screen').then((module) => ({
    default: module.EditRequirementTemplateScreen,
  })),
);
const JurisdictionDigitalPermitScreen = lazy(() =>
  import('../requirement-template/screens/jurisdiction-digital-permit-screen').then((module) => ({
    default: module.JurisdictionDigitalPermitScreen,
  })),
);
const JurisdictionEditDigitalPermitScreen = lazy(() =>
  import('../requirement-template/screens/jurisdiction-edit-digital-permit-screen').then((module) => ({
    default: module.JurisdictionEditDigitalPermitScreen,
  })),
);
const JurisdictionApiMappingsSetupIndexScreen = lazy(() =>
  import('../requirement-template/screens/jurisdiction-api-mappings-setup-index-screen').then((module) => ({
    default: module.JurisdictionApiMappingsSetupIndexScreen,
  })),
);

const EditJurisdictionApiMappingScreen = lazy(() =>
  import('../requirement-template/screens/edit-jurisdiction-api-mapping-screen').then((module) => ({
    default: module.EditJurisdictionApiMappingScreen,
  })),
);

const RequirementTemplatesScreen = lazy(() =>
  import('../requirement-template/screens/requirement-template-screen').then((module) => ({
    default: module.RequirementTemplatesScreen,
  })),
);
const TemplateVersionScreen = lazy(() =>
  import('../requirement-template/screens/template-version-screen').then((module) => ({
    default: module.TemplateVersionScreen,
  })),
);

const ExportTemplatesScreen = lazy(() =>
  import('../jurisdictions/exports/export-templates-screen').then((module) => ({
    default: module.ExportTemplatesScreen,
  })),
);

const RequirementsLibraryScreen = lazy(() =>
  import('../requirements-library').then((module) => ({ default: module.RequirementsLibraryScreen })),
);
const StepCodeForm = lazy(() => import('../step-code').then((module) => ({ default: module.StepCodeForm })));
const StepCodeChecklistPDFViewer = lazy(() =>
  import('../step-code/checklist/pdf-content/viewer').then((module) => ({
    default: module.StepCodeChecklistPDFViewer,
  })),
);
const SiteConfigurationManagementScreen = lazy(() =>
  import('../super-admin/site-configuration-management').then((module) => ({
    default: module.SiteConfigurationManagementScreen,
  })),
);
const SitewideMessageScreen = lazy(() =>
  import('../super-admin/site-configuration-management/sitewide-message-screen').then((module) => ({
    default: module.SitewideMessageScreen,
  })),
);
const HelpDrawerSetupScreen = lazy(() =>
  import('../super-admin/site-configuration-management/help-drawer-setup-screen').then((module) => ({
    default: module.HelpDrawerSetupScreen,
  })),
);

const RevisionReasonSetupScreen = lazy(() =>
  import('../super-admin/site-configuration-management/revision-reason-setup-screen').then((module) => ({
    default: module.RevisionReasonSetupScreen,
  })),
);

const LandingSetupScreen = lazy(() =>
  import('../super-admin/site-configuration-management/landing-setup-screen').then((module) => ({
    default: module.LandingSetupScreen,
  })),
);

const AdminUserIndexScreen = lazy(() =>
  import('../super-admin/site-configuration-management/users-screen').then((module) => ({
    default: module.AdminUserIndexScreen,
  })),
);

const ReportingScreen = lazy(() =>
  import('../super-admin/reporting/reporting-screen').then((module) => ({ default: module.ReportingScreen })),
);

const ExportTemplateSummaryScreen = lazy(() =>
  import('../super-admin/reporting/export-template-summary-screen').then((module) => ({
    default: module.ExportTemplateSummaryScreen,
  })),
);

const EarlyAccessScreen = lazy(() =>
  import('../super-admin/early-access/early-access-screen').then((module) => ({
    default: module.EarlyAccessScreen,
  })),
);

const EarlyAccessRequirementTemplatesIndexScreen = lazy(() =>
  import('../super-admin/early-access/requirement-templates').then((module) => ({
    default: module.EarlyAccessRequirementTemplatesIndexScreen,
  })),
);

const EarlyAccessRequirementTemplateScreen = lazy(() =>
  import('../super-admin/early-access/requirement-templates/early-access-requirement-template-screen').then(
    (module) => ({
      default: module.EarlyAccessRequirementTemplateScreen,
    }),
  ),
);

const NewEarlyAccessRequirementTemplateScreen = lazy(() =>
  import('../super-admin/early-access/requirement-templates/new-early-access-requirement-template-screen').then(
    (module) => ({
      default: module.NewEarlyAccessRequirementTemplateScreen,
    }),
  ),
);

const EditEarlyAccessRequirementTemplateScreen = lazy(() =>
  import('../super-admin/early-access/requirement-templates/edit-early-access-requirement-template-screen').then(
    (module) => ({
      default: module.EditEarlyAccessRequirementTemplateScreen,
    }),
  ),
);

const EarlyAccessRequirementsLibraryScreen = lazy(() =>
  import('../super-admin/early-access/requirements-library').then((module) => ({
    default: module.EarlyAccessRequirementsLibraryScreen,
  })),
);

const AcceptInvitationScreen = lazy(() =>
  import('../programs/accept-invitation-screen').then((module) => ({ default: module.AcceptInvitationScreen })),
);
//const InviteScreen = lazy(() => import('../users/invite-screen').then((module) => ({ default: module.InviteScreen })));
const InviteEmployeeScreen = lazy(() =>
  import('../users/invite-employee-screen').then((module) => ({ default: module.InviteEmployeeScreen })),
);
const ProfileScreen = lazy(() =>
  import('../users/profile-screen').then((module) => ({ default: module.ProfileScreen })),
);
const RedirectScreen = lazy(() =>
  import('../../shared/base/redirect-screen').then((module) => ({ default: module.RedirectScreen })),
);

const Footer = lazy(() => import('../../shared/base/footer').then((module) => ({ default: module.Footer })));

const APP_TITLE_SUFFIX = 'ESP';
const DEFAULT_ROUTE_TITLE = 'Energy Savings Program';

const ROUTE_TITLE_BY_PATH: Record<string, string> = {
  '/': 'Home',
  '/admin': 'Admin Login',
  '/admin-mgr': 'Admin Manager Login',
  '/ai-contractor-dashboard': 'AI Contractor Dashboard',
  '/api-settings/api-mappings': 'API Mappings',
  '/applications': 'Applications',
  '/audit-log': 'Audit Log',
  '/awhp-product-list-admin': 'AWHP Product List Admin',
  '/blank-applications': 'Blank Applications',
  '/check-eligible': 'Eligibility Check',
  '/claims-rbac-admin': 'Role Based Access Control',
  '/configuration-management': 'Configuration Management',
  '/configuration-management/help-drawer-setup': 'Help Drawer Setup',
  '/configuration-management/invite-employee': 'Invite Employee',
  '/configuration-management/landing-setup': 'Landing Setup',
  '/configuration-management/revision-reason-setup': 'Revision Reason Setup',
  '/configuration-management/sitewide-banner': 'Sitewide Banner',
  '/configuration-management/users': 'Admin Users',
  '/configuration-management/users/invite': 'Invite Admin User',
  '/configure-users': 'Configure Users',
  '/contact': 'Contact',
  '/confirmed': 'Email Confirmed',
  '/contractor': 'Contractor Login',
  '/contractor-dashboard': 'Contractor Dashboard',
  '/contractor/upload-invoices': 'Upload Invoices',
  '/contractor-management': 'Contractor Management',
  '/contractor-program-resources': 'Contractor Program Resources',
  '/contractorfixsimulation': 'Contractor Fix Simulation',
  '/contractors-admin': 'Contractors Admin',
  '/digital-building-permits': 'Digital Building Permits',
  '/downloads-admin': 'Downloads Admin',
  '/early-access': 'Early Access',
  '/early-access/requirement-templates': 'Early Access Requirement Templates',
  '/early-access/requirement-templates/new': 'New Early Access Requirement Template',
  '/early-access/requirements-library': 'Early Access Requirements Library',
  '/eligibilitycode-editor': 'Eligibility Code Editor',
  '/eligibilitycodes-admin': 'Eligibility Codes Admin',
  '/get-support': 'Support',
  '/heat-pump-product-list-admin': 'Heat Pump Product List Admin',
  '/hello-ai-admin': 'Hello AI Admin',
  '/ingest-runs-admin': 'Ingest Runs',
  '/herv-product-list-admin': 'HERV ENERGY STAR Product List Admin',
  '/hpwh-product-list-admin': 'HPWH Product List Admin',
  '/invoice-supporting-documents-admin': 'Invoice Supporting Documents Admin',
  '/invoice-versions-admin': 'Invoice Versions Admin',
  '/invoices-admin': 'Invoices Admin',
  '/login': 'Login',
  '/new-application': 'New Application',
  '/new-invoice': 'New Invoice',
  '/not-found': 'Not Found',
  '/ohpa-product-list-admin': 'OHPA Product List Admin',
  '/vent-fan-product-list-admin': 'ENERGY STAR Fan Product List Admin',
  '/profile': 'Profile',
  '/profile/eula': 'Terms',
  '/programs': 'Programs',
  '/programs/new-program': 'New Program',
  '/reporting': 'Reporting',
  '/reporting/export-template-summary': 'Export Template Summary',
  '/reports-volume-value': 'Volume Value Report',
  '/requirement-templates': 'Requirement Templates',
  '/requirement-templates/new-template': 'New Requirement Template',
  '/requirements-library': 'Requirements Library',
  '/conversation-messages-admin': 'Contractor Conversation',
  '/submission-inbox': 'Submission Inbox',
  '/submission-simulator-admin': 'New Invoice Simulator',
  '/supported-applications': 'Supported Applications',
  '/supporting-document-type-fields-admin': 'Supporting Document Type Fields Admin',
  '/supporting-document-types-admin': 'Supporting Document Types Admin',
  '/sys-admin': 'System Admin Login',
  '/terms': 'Terms',
  '/user-editor': 'User Editor',
  '/users-admin': 'Users Admin',
  '/validation-rules-admin': 'Validation Rules Admin',
  '/validation-rules-alphabetic-admin': 'Validation Rules Alphabetic Admin',
  '/validation-fields-alphabetic-admin': 'GenAI Fields at a Glance',
  '/validation-rules-config': 'Validation Rules Config',
  '/test-harness/suites': 'Test Suites',
  '/test-harness/model-comparisons': 'Model Comparison Runs',
  '/test-harness/model-comparisons/new': 'New Model Comparison',
  '/test-harness/rule-comparisons': 'Rule Comparison Runs',
  '/test-harness/rule-comparisons/new': 'New Rule Comparison',
  '/test-harness/regressions': 'Regression Runs',
  '/test-harness/regressions/new': 'New Regression Run',
  '/welcome': 'Welcome',
  '/welcome/contractor': 'Contractor Welcome',
  '/welcome/contractor/invite': 'Contractor Invite',
};

const ROUTE_TITLE_PATTERNS: Array<[RegExp, string]> = [
  [/^\/advice-refresh-simulation-admin$/, 'AI Advice Refresh Simulator'],
  [/^\/applications\/[^/]+$/, 'Application Review'],
  [/^\/applications\/[^/]+\/edit$/, 'Edit Application'],
  [/^\/applications\/[^/]+\/edit\/step-code$/, 'Step Code'],
  [/^\/applications\/[^/]+\/withdrawl-success$/, 'Withdrawal Success'],
  [/^\/applications\/[^/]+\/ineligible-success$/, 'Ineligible Success'],
  [/^\/applications\/[^/]+\/screened-in-success$/, 'Screened In Success'],
  [/^\/applications\/[^/]+\/approved-pending-success$/, 'Approved Pending Success'],
  [/^\/applications\/[^/]+\/approved-paid-success$/, 'Approved Paid Success'],
  [/^\/applications\/[^/]+\/successful-submission$/, 'Submission Success'],
  [/^\/applications\/[^/]+\/successful-training-pending$/, 'Training Pending Success'],
  [/^\/applications\/[^/]+\/onboarding-approved$/, 'Onboarding Approved'],
  [/^\/applications\/[^/]+\/successful-update$/, 'Update Success'],
  [/^\/blank-template\/[^/]+$/, 'Blank Template'],
  [/^\/configuration-management\/users\/invite$/, 'Invite Admin User'],
  [/^\/configure-users\/[^/]+\/invite$/, 'Invite Program User'],
  [/^\/configure-users\/[^/]+\/users$/, 'Program Users'],
  [/^\/contractor\/applications\/[^/]+\/edit$/, 'Contractor Application Edit'],
  [/^\/contractor\/sessions\/[^/]+\/invoices\/[^/]+\/fix$/, 'Contractor Invoice Fix'],
  [/^\/contractor\/sessions\/[^/]+\/invoices\/[^/]+\/messages$/, 'Invoice Messages'],
  [/^\/contractor\/sessions\/[^/]+\/invoices\/[^/]+\/review$/, 'Contractor Invoice Review'],
  [/^\/contractor-management\/[^/]+\/employees$/, 'Contractor Employees'],
  [/^\/contractor-management\/[^/]+\/invite-employee$/, 'Invite Contractor Employee'],
  [/^\/contractor-management\/[^/]+\/remove\/removal-confirmation$/, 'Contractor Remove Confirmation'],
  [/^\/contractor-management\/[^/]+\/remove\/removal-reason$/, 'Contractor Remove Reason'],
  [/^\/contractor-management\/[^/]+\/suspend\/confirmation$/, 'Contractor Suspend Confirmation'],
  [/^\/contractor-management\/[^/]+\/suspend\/reason$/, 'Contractor Suspend Reason'],
  [/^\/contractor-management\/[^/]+\/unsuspend-confirmation$/, 'Contractor Unsuspend Confirmation'],
  [/^\/digital-building-permits\/[^/]+\/edit$/, 'Edit Digital Building Permit'],
  [/^\/early-access\/requirement-templates\/[^/]+$/, 'Early Access Requirement Template'],
  [/^\/early-access\/requirement-templates\/[^/]+\/edit$/, 'Edit Early Access Requirement Template'],
  [/^\/invoice-versions\/[^/]+$/, 'Invoice Version'],
  [/^\/invoice-versions\/[^/]+\/review$/, 'Invoice Version Review'],
  [/^\/invoice-versions-by-version\/[^/]+\/read$/, 'Invoice Version Read'],
  [/^\/invoices\/[^/]+\/review$/, 'Invoice Review'],
  [/^\/test-harness\/suites\/[^/]+\/cases$/, 'Test Suite Cases'],
  [/^\/test-harness\/model-comparisons\/[^/]+(?:\/results)?$/, 'Model Comparison Results'],
  [/^\/test-harness\/rule-comparisons\/[^/]+$/, 'Rule Comparison Results'],
  [/^\/test-harness\/regressions\/[^/]+$/, 'Regression Run Results'],
  [/^\/jurisdictions\/[^/]+$/, 'Jurisdiction'],
  [/^\/jurisdictions\/[^/]+\/api-settings\/api-mappings\/digital-building-permits\/[^/]+\/edit$/, 'Edit API Mapping'],
  [/^\/jurisdictions\/[^/]+\/configuration-management$/, 'Jurisdiction Configuration'],
  [/^\/programs\/[^/]+\/accept-invitation$/, 'Accept Invitation'],
  [/^\/programs\/[^/]+\/api-settings$/, 'Program API Settings'],
  [/^\/programs\/[^/]+\/edit$/, 'Edit Program'],
  [/^\/programs\/[^/]+\/invite$/, 'Invite Program User'],
  [/^\/programs\/[^/]+\/users$/, 'Program Users'],
  [/^\/rejection-reason\/[^/]+$/, 'Rejection Reason'],
  [/^\/requirement-templates\/[^/]+\/edit$/, 'Edit Requirement Template'],
  [/^\/sessions\/[^/]+\/invoices\/[^/]+\/read$/, 'Invoice Read'],
  [/^\/template-versions\/[^/]+$/, 'Template Version'],
];

const getRouteTitle = (pathname: string) => {
  const normalizedPath = pathname.replace(/\/+$/, '') || '/';
  const exactTitle = ROUTE_TITLE_BY_PATH[normalizedPath];
  if (exactTitle) return exactTitle;

  const matchedRouteTitle = ROUTE_TITLE_PATTERNS.find(([routePattern]) => routePattern.test(normalizedPath))?.[1];
  return matchedRouteTitle || DEFAULT_ROUTE_TITLE;
};

const getDocumentTitle = (pathname: string) => `${getRouteTitle(pathname)} - ${APP_TITLE_SUFFIX}`;

export const Navigation = observer(() => {
  const { sessionStore, siteConfigurationStore } = useMst();
  const { isLoggingOut } = sessionStore;
  const { displaySitewideMessage, sitewideMessage } = siteConfigurationStore;
  const { validateToken, isValidating } = sessionStore;

  useEffect(() => {
    validateToken();
  }, []);

  if (isLoggingOut) return <LoadingScreen />;

  return (
    <BrowserRouter>
      <Box pos="relative" w="full">
        <Box pos="absolute" top={0} zIndex="toast" w="full">
          <FlashMessage />
        </Box>
      </Box>
      {displaySitewideMessage && (
        <Center h={16} bg={siteConfigurationStore.sitewideMessageColor || 'theme.yellowLight'}>
          {sitewideMessage}
        </Center>
      )}
      {isValidating ? (
        <LoadingScreen />
      ) : (
        <ClaimsAccessProvider>
          <NavBar />
          <Suspense fallback={<LoadingScreen />}>
            <AppRoutes />

            <Footer />
          </Suspense>
        </ClaimsAccessProvider>
      )}
    </BrowserRouter>
  );
});

const AppRoutes = observer(() => {
  const rootStore = useMst();
  const { sessionStore, userStore, uiStore } = rootStore;
  const { loggedIn, tokenExpired } = sessionStore;
  const location = useLocation();
  const background = location.state && location.state.background;
  const enableStepCodeRoute = location.state?.enableStepCodeRoute;

  const { currentUser } = userStore;
  const { can: canUseClaimsFunction, loading: claimsAccessLoading } = useClaimsAccess();
  const { afterLoginPath, setAfterLoginPath, resetAuth, entryPoint } = sessionStore;

  const navigate = useNavigate();
  const { t } = useTranslation();

  // Track page views on route changes (Snowplow)
  useEffect(() => {
    // Skip tracking for BC Services Card login route and external BC Gov login pages
    if (
      location.pathname.includes('/bcsc') ||
      window.location.href.includes('idtest.gov.bc.ca') ||
      window.location.href.includes('id.gov.bc.ca')
    ) {
      return;
    }

    trackPageViewEvent();
  }, [location.pathname]);

  useEffect(() => {
    document.title = getDocumentTitle(location.pathname);
  }, [location.pathname]);

  useEffect(() => {
    if (tokenExpired) {
      const isContractorFlow =
        entryPoint === 'isContractor' ||
        currentUser?.isContractor ||
        sessionStorage.getItem('isContractorFlow') === 'true' ||
        location.pathname.startsWith('/contractor');

      const isAdminFlow =
        entryPoint === 'isAdmin' ||
        entryPoint === 'isAdminMgr' ||
        entryPoint === 'isSysAdmin' ||
        currentUser?.isAdmin ||
        currentUser?.isAdminManager ||
        currentUser?.isSystemAdmin;

      resetAuth();
      setAfterLoginPath(location.pathname);
      if (isContractorFlow) {
        navigate('/contractor');
      } else if (isAdminFlow) {
        navigate('/admin');
      } else {
        navigate('/login');
      }
      uiStore.flashMessage.show(EFlashMessageStatus.warning, t('auth.tokenExpired'), null);
    }
  }, [tokenExpired, entryPoint, currentUser, location.pathname, navigate, resetAuth, setAfterLoginPath, t, uiStore]);

  useEffect(() => {
    const storedPath = sessionStorage.getItem('afterLoginPath') || afterLoginPath;
    if (loggedIn && storedPath) {
      sessionStorage.removeItem('afterLoginPath');
      setAfterLoginPath(null);
      navigate(storedPath);
    }
  }, [afterLoginPath, loggedIn]);

  const superAdminOnlyRoutes = (
    <>
      <Route path="/programs" element={<ProgramsIndexScreen />} />
      <Route path="/programs/new-program" element={<NewProgramScreen />} />
      <Route path="/programs/:programId/edit" element={<NewProgramScreen />} />
      <Route path="/programs/:programId/users" element={<ProgramUserIndexScreen />} />
      <Route path="/programs/:programId/invite" element={<ProgramInviteUserScreen />} />
      <Route path="/programs/:programId/api-settings" element={<ExternalApiKeysIndexScreen />}>
        <Route path="create" element={<ExternalApiKeyModalSubRoute />} />
        <Route path=":externalApiKeyId/manage" element={<ExternalApiKeyModalSubRoute />} />
      </Route>
      {/* <Route path="/jurisdictions/new" element={<NewJurisdictionScreen />} /> */}
      <Route path="/requirements-library" element={<RequirementsLibraryScreen />} />
      <Route path="/early-access/requirements-library" element={<EarlyAccessRequirementsLibraryScreen />} />
      <Route path="/requirement-templates" element={<RequirementTemplatesScreen />} />
      <Route path="/early-access/requirement-templates" element={<EarlyAccessRequirementTemplatesIndexScreen />} />
      <Route path="/early-access/requirement-templates/new" element={<NewEarlyAccessRequirementTemplateScreen />} />
      <Route
        path="/early-access/requirement-templates/:requirementTemplateId/edit"
        element={<EditEarlyAccessRequirementTemplateScreen />}
      />
      <Route path="/requirement-templates/new-template" element={<NewRequirementTemplateScreen />} />
      <Route path="/requirement-templates/:requirementTemplateId/edit" element={<EditRequirementTemplateScreen />} />
      <Route path="/template-versions/:templateVersionId" element={<TemplateVersionScreen />} />
      <Route path="/configuration-management" element={<SiteConfigurationManagementScreen />} />
      <Route path="/configuration-management/sitewide-banner" element={<SitewideMessageScreen />} />
      <Route path="/configuration-management/help-drawer-setup" element={<HelpDrawerSetupScreen />} />
      <Route path="/configuration-management/revision-reason-setup" element={<RevisionReasonSetupScreen />} />
      <Route path="/configuration-management/landing-setup" element={<LandingSetupScreen />} />
      <Route path="/configuration-management/users" element={<AdminUserIndexScreen />} />
      <Route path="/configuration-management/users/invite" element={<AdminInviteScreen />} />
      <Route path="/configuration-management/invite-employee" element={<InviteEmployeeScreen />} />
      <Route path="/audit-log" element={<AuditLogScreen />} />
      <Route path="/reporting" element={<ReportingScreen />} />
      <Route path="/reporting/export-template-summary" element={<ExportTemplateSummaryScreen />} />
      <Route path="/early-access" element={<EarlyAccessScreen />} />
    </>
  );

  const adminManagerRoutes = (
    <>
      <Route path="/configure-users" element={<ProgramsIndexScreen />} />
      <Route path="/configure-users/:programId/users" element={<ProgramUserIndexScreen />} />
      <Route path="/configure-users/:programId/invite" element={<ProgramInviteUserScreen />} />
      <Route path="/audit-log" element={<AuditLogScreen />} />
    </>
  );

  const adminManagerOrAdmin = (
    <>
      <Route path="/submission-inbox" element={<ProgramSubmissionInboxScreen />} />
      <Route path="/applications/:permitApplicationId" element={<ReviewPermitApplicationScreen />} />
      <Route path="/blank-template/:templateVersionId" element={<BlankTemplateScreen />} />
      <Route path="/contractor-management" element={<ContractorManagementScreen />} />
      <Route path="/contractor-management/:contractorId/employees" element={<ContractorEmployeeIndexScreen />} />
      <Route path="/contractor-management/:contractorId/invite-employee" element={<InviteEmployeeScreen />} />
      <Route path="/contractor-management/:contractorId/suspend/reason" element={<SuspendReasonPage />} />
      <Route
        path="/contractor-management/:contractorId/suspend/confirmation"
        element={<ContractorSuspendConfirmedScreen />}
      />
      <Route
        path="/contractor-management/:contractorId/unsuspend-confirmation"
        element={<ContractorUnsuspendConfirmedScreen />}
      />
      <Route path="/contractor-management/:contractorId/remove/removal-reason" element={<RemoveReasonPage />} />
      <Route
        path="/contractor-management/:contractorId/remove/removal-confirmation"
        element={<ContractorRemoveConfirmedScreen />}
      />
      <Route path="/contractor-program-resources" element={<ContractorProgramResourcesScreen />} />
      {/* view blank applications and view supported applications to go here */}
      {import.meta.env.DEV && (
        <>
          <Route
            path="/applications/:permitApplicationId/pdf-content"
            element={<PermitApplicationPDFViewer mode={'pdf'} />}
          />
          <Route
            path="/applications/:permitApplicationId/pdf-html"
            element={<PermitApplicationPDFViewer mode={'html'} />}
          />
          <Route
            path="/applications/:permitApplicationId/step-code-pdf-content"
            element={<StepCodeChecklistPDFViewer mode={'pdf'} />}
          />
          <Route
            path="/applications/:permitApplicationId/step-code-pdf-html"
            element={<StepCodeChecklistPDFViewer mode={'html'} />}
          />
        </>
      )}
    </>
  );

  const reviewManagerOnlyRoutes = (
    <>
      <Route
        path="/digital-building-permits/:templateVersionId/edit"
        element={<JurisdictionEditDigitalPermitScreen />}
      />
      <Route
        path="/jurisdictions/:jurisdictionId/configuration-management"
        element={<ConfigurationManagementScreen />}
      />
      <Route path="/digital-building-permits" element={<JurisdictionDigitalPermitScreen />} />
      <Route path="/api-settings/api-mappings" element={<JurisdictionApiMappingsSetupIndexScreen />} />
      <Route
        path="/jurisdictions/:jurisdictionId/api-settings/api-mappings/digital-building-permits/:templateVersionId/edit"
        element={<EditJurisdictionApiMappingScreen />}
      />
      <Route
        path="/api-settings/api-mappings/digital-building-permits/:templateVersionId/edit"
        element={<EditJurisdictionApiMappingScreen />}
      />
    </>
  );

  //const mustAcceptEula = loggedIn && !currentUser.eulaAccepted && !currentUser.isSuperAdmin;
  const mustAcceptEula = loggedIn && currentUser && !currentUser.eulaAccepted;
  const isClaimsContractorUser = Boolean(loggedIn && !mustAcceptEula && currentUser && currentUser.isContractor);
  const canUseClaimsContractorPortal = Boolean(
    loggedIn && !mustAcceptEula && currentUser && canUseClaimsFunction('claims.contractor_portal'),
  );
  const canUseClaimsOperations = Boolean(
    loggedIn && !mustAcceptEula && currentUser && canUseClaimsFunction('claims.operations'),
  );
  const canUseClaimsConfiguration = Boolean(
    loggedIn && !mustAcceptEula && currentUser && canUseClaimsFunction('claims.configuration'),
  );
  const canUseClaimsTestTools = Boolean(
    loggedIn && !mustAcceptEula && currentUser && canUseClaimsFunction('claims.test_tools'),
  );
  const canManageClaimsRbac = Boolean(
    loggedIn && !mustAcceptEula && currentUser && canUseClaimsFunction('claims.role_functions'),
  );

  if (loggedIn && currentUser && claimsAccessLoading) return <LoadingScreen />;

  return (
    <>
      <Routes location={background || location}>
        {mustAcceptEula && (
          // Onboarding step 1: EULA
          <Route path="/" element={<EULAScreen />} />
        )}
        {loggedIn && currentUser && currentUser.eulaAccepted && !currentUser.isReviewed && (
          // Onboarding step 2: confirm email
          <Route path="/" element={<ProfileScreen />} />
        )}
        {loggedIn ? (
          <Route path="/" element={<HomeScreen />} />
        ) : (
          <Route path="/" element={<RedirectScreen path="/welcome" />} />
        )}
        <Route
          element={
            <ProtectedRoute
              isAllowed={isClaimsContractorUser}
              redirectPath={(mustAcceptEula && '/') || (loggedIn && '/not-found') || '/contractor'}
            />
          }
        >
          <Route path="/contractor-dashboard" element={<ContractorDashboardScreen />} />
          <Route path="/contractor/applications/:permitApplicationId/edit" element={<EditPermitApplicationScreen />} />
        </Route>

        <Route
          element={
            <ProtectedRoute
              isAllowed={canUseClaimsContractorPortal}
              redirectPath={(mustAcceptEula && '/') || (loggedIn && '/not-found') || '/contractor'}
            />
          }
        >
          <Route path="/ai-contractor-dashboard" element={<AiContractorDashboardScreen />} />
          <Route path="/contractor/upload-invoices" element={<ContractorUploadInvoicesScreen />} />
          <Route
            path="/contractor/sessions/:sessionId/invoices/:invoiceId/review"
            element={<ContractorInvoiceReviewScreen />}
          />
          <Route
            path="/contractor/sessions/:sessionId/invoices/:invoiceId/fix"
            element={<ContractorFixUploadScreen />}
          />
          <Route
            path="/contractor/sessions/:sessionId/invoices/:invoiceId/messages"
            element={<ContractorInvoiceMessagesScreen />}
          />
        </Route>

        <Route
          element={<ProtectedRoute isAllowed={loggedIn && !mustAcceptEula} redirectPath={mustAcceptEula && '/'} />}
        >
          <Route path="/applications" element={<EnergySavingsApplicationIndexScreen />} />
          <Route path="/new-application" element={<NewApplicationScreen />} />
          <Route path="/new-invoice" element={<NewInvoiceScreen />} />
          <Route path="/blank-applications" element={<NewApplicationScreen />} />
          <Route path="/supported-applications" element={<EnergySavingsApplicationIndexScreen />} />
          <Route path="/applications/:permitApplicationId/edit" element={<EditPermitApplicationScreen />}>
            <Route path="step-code" element={<StepCodeForm />} />
          </Route>
          <Route path="/applications/:permitApplicationId/withdrawl-success" element={<SuccessfulWithdrawalScreen />} />
          <Route
            path="/applications/:permitApplicationId/ineligible-success"
            element={<SuccessfulIneligibleScreen />}
          />
          <Route
            path="/applications/:permitApplicationId/screened-in-success"
            element={<SuccessfulScreenedInScreen />}
          />
          <Route
            path="/applications/:permitApplicationId/approved-pending-success"
            element={<SuccessfulApprovedPendingScreen />}
          />
          <Route
            path="/applications/:permitApplicationId/approved-paid-success"
            element={<SuccessfulApprovedPaidScreen />}
          />
          <Route
            path="/applications/:permitApplicationId/successful-submission"
            element={<SuccessfulSubmissionScreen />}
          />
          <Route
            path="/applications/:permitApplicationId/successful-training-pending"
            element={<SuccessfulTrainingPendingScreen />}
          />
          <Route
            path="/applications/:permitApplicationId/onboarding-approved"
            element={<SuccessfulOnboardingApprovalScreen />}
          />
          <Route path="/applications/:permitApplicationId/successful-update" element={<SuccessfulUpdateScreeen />} />
        </Route>

        <Route element={<ProtectedRoute isAllowed={loggedIn} />}>
          <Route path="/profile" element={<ProfileScreen />} />
        </Route>

        <Route element={<ProtectedRoute isAllowed={loggedIn && !currentUser?.isSuperAdmin} />}>
          <Route path="/profile/eula" element={<EULAScreen withClose />} />
        </Route>

        <Route
          element={
            <ProtectedRoute
              isAllowed={
                loggedIn && !mustAcceptEula && currentUser && (currentUser.isAdminManager || currentUser.isSuperAdmin)
              }
              redirectPath={(mustAcceptEula && '/') || (loggedIn && '/not-found')}
            />
          }
        >
          {adminManagerRoutes}
        </Route>

        <Route
          element={
            <ProtectedRoute
              isAllowed={loggedIn && currentUser && currentUser.isSuperAdmin}
              redirectPath={loggedIn && '/not-found'}
            />
          }
        >
          {superAdminOnlyRoutes}
        </Route>

        <Route
          element={
            <ProtectedRoute
              isAllowed={
                loggedIn && !mustAcceptEula && currentUser && (currentUser.isAdminManager || currentUser.isAdmin)
              }
              redirectPath={(mustAcceptEula && '/') || (loggedIn && '/not-found')}
            />
          }
        >
          {adminManagerOrAdmin}
        </Route>

        <Route
          element={
            <ProtectedRoute
              isAllowed={
                loggedIn && !mustAcceptEula && currentUser && currentUser.isReviewStaff && !currentUser.isReviewer
              }
              redirectPath={(mustAcceptEula && '/') || (loggedIn && '/not-found')}
            />
          }
        >
          {reviewManagerOnlyRoutes}
        </Route>

        {/* TODO: we need to add security around some of the role logins */}
        <Route element={<ProtectedRoute isAllowed={!loggedIn} redirectPath="/" />}>
          <Route path="/login" element={<LoginScreen />} />
          <Route path="/contractor" element={<AdminPortalLogin isContractor />} />
          <Route path="/admin" element={<AdminPortalLogin isAdmin />} />
          {/* <Route path="/psr" element={<AdminPortalLogin isPSR />} /> */}
          <Route path="/admin-mgr" element={<AdminPortalLogin isAdminMgr />} />
          <Route path="/sys-admin" element={<AdminPortalLogin isSysAdmin />} />
        </Route>
        {/* Public Routes */}

        <Route path="/rejection-reason/:permitApplicationId" element={<RejectApplicationScreen />} />
        <Route path="/programs/:programId/accept-invitation" element={<AcceptInvitationScreen />} />
        {/* <Route path="/accept-invitation" element={<AcceptInvitationScreen />} /> */}

        <Route path="/contact" element={<ContactScreen />} />
        <Route path="/confirmed" element={<EmailConfirmedScreen />} />

        {/* sbra20260130 claims subsytem route info */}
        <Route
          element={
            <ProtectedRoute
              isAllowed={canUseClaimsOperations}
              redirectPath={(mustAcceptEula && '/') || (loggedIn && '/not-found') || '/admin'}
            />
          }
        >
          <Route path="/invoice-versions/:id" element={<InvoiceVersionShowScreen />} />
          <Route path="/invoices/:invoiceId/review" element={<InvoiceVersionShowScreen />} />
          <Route path="/invoice-versions/:id/review" element={<InvoiceVersionShowScreen />} />
          <Route path="/sessions/:sessionId/invoices/:invoiceId/read" element={<InvoiceVersionShowScreen />} />
          <Route path="/invoice-versions-by-version/:invoiceVersionId/read" element={<InvoiceVersionShowScreen />} />
          <Route path="/invoices-admin" element={<InvoicesAdminScreen />} />
          <Route path="/invoice-versions-admin" element={<InvoiceVersionsAdminScreen />} />
          <Route path="/invoice-supporting-documents-admin" element={<InvoiceSupportingDocumentsAdminScreen />} />
          <Route path="/conversation-messages-admin" element={<ConversationMessagesAdminScreen />} />
          <Route path="/reports-volume-value" element={<ReportsVolumeValueScreen />} />
        </Route>

        <Route
          element={
            <ProtectedRoute
              isAllowed={canUseClaimsConfiguration}
              redirectPath={(mustAcceptEula && '/') || (loggedIn && '/not-found') || '/admin'}
            />
          }
        >
          <Route path="/validation-rules-admin" element={<ValidationRulesAdminScreen />} />
          <Route path="/validation-rules-alphabetic-admin" element={<ValidationRulesAlphabeticAdminScreen />} />
          <Route path="/validation-fields-alphabetic-admin" element={<ValidationFieldsAlphabeticAdminScreen />} />
          <Route path="/validation-rules-config" element={<ValidationRulesConfigScreen />} />
          <Route path="/supporting-document-types-admin" element={<SupportingDocumentTypesAdminScreen />} />
          <Route path="/supporting-document-type-fields-admin" element={<SupportingDocumentTypeFieldsAdminScreen />} />
          <Route path="/downloads-admin" element={<DownloadsAdminScreen />} />
          <Route path="/heat-pump-product-list-admin" element={<HeatPumpProductListAdminScreen />} />
          <Route path="/hpwh-product-list-admin" element={<HpwhProductListAdminScreen />} />
          <Route path="/awhp-product-list-admin" element={<AwhpProductListAdminScreen />} />
          <Route path="/ohpa-product-list-admin" element={<OhpaProductListAdminScreen />} />
          <Route path="/herv-product-list-admin" element={<HervProductListAdminScreen />} />
          <Route path="/vent-fan-product-list-admin" element={<VentFanProductListAdminScreen />} />
          <Route path="/ingest-runs-admin" element={<IngestRunsAdminScreen />} />
        </Route>

        <Route
          element={
            <ProtectedRoute
              isAllowed={canUseClaimsTestTools}
              redirectPath={(mustAcceptEula && '/') || (loggedIn && '/not-found') || '/admin'}
            />
          }
        >
          <Route path="/hello-ai-admin" element={<HelloAiAdminScreen />} />
          <Route path="/contractorfixsimulation" element={<ContractorFixSimulationAdminScreen />} />
          <Route path="/advice-refresh-simulation-admin" element={<AdviceRefreshSimulationAdminScreen />} />
          <Route path="/submission-simulator-admin" element={<SubmissionSimulatorAdminScreen />} />
          <Route path="/contractors-admin" element={<ContractorsAdminScreen />} />
          <Route path="/eligibilitycodes-admin" element={<EligibilitycodesAdminScreen />} />
          <Route path="/users-admin" element={<UsersAdminScreen />} />
          <Route path="/user-editor" element={<UserEditorScreen />} />
          <Route path="/eligibilitycode-editor" element={<EligibilitycodeEditorScreen />} />
          <Route path="/test-harness/suites" element={<TestSuitesScreen />} />
          <Route path="/test-harness/suites/:testsuiteId/cases" element={<TestSuiteCasesScreen />} />
          <Route path="/test-harness/model-comparisons" element={<ModelComparisonsScreen />} />
          <Route path="/test-harness/model-comparisons/new" element={<NewModelComparisonScreen />} />
          <Route
            path="/test-harness/model-comparisons/:modelComparisonId/results"
            element={<ModelComparisonResultsScreen />}
          />
          <Route path="/test-harness/model-comparisons/:modelComparisonId" element={<ModelComparisonResultsScreen />} />
          <Route path="/test-harness/rule-comparisons" element={<RuleComparisonsScreen />} />
          <Route path="/test-harness/rule-comparisons/new" element={<NewRuleComparisonScreen />} />
          <Route path="/test-harness/rule-comparisons/:ruleComparisonId" element={<RuleComparisonResultsScreen />} />
          <Route path="/test-harness/regressions" element={<RegressionRunsScreen />} />
          <Route path="/test-harness/regressions/new" element={<NewRegressionRunScreen />} />
          <Route path="/test-harness/regressions/:regressionRunId" element={<RegressionRunResultsScreen />} />
        </Route>

        <Route
          element={
            <ProtectedRoute
              isAllowed={canManageClaimsRbac}
              redirectPath={(mustAcceptEula && '/') || (loggedIn && '/not-found') || '/admin'}
            />
          }
        >
          <Route path="/claims-rbac-admin" element={<ClaimsRbacAdminScreen />} />
        </Route>
        {/* end sbra20260130 */}

        <Route path="/welcome" element={<LandingScreen />} />
        <Route path="/welcome/contractor" element={<ContractorLandingScreen />} />
        <Route path="/welcome/contractor/invite" element={<ContractorOnboardingImport />} />
        <Route path="/terms" element={<EULAScreen withClose />} />
        <Route path="/check-eligible" element={<EligibilityCheck />} />
        <Route path="/get-support" element={<SupportScreen />} />
        <Route
          path="/early-access/requirement-templates/:requirementTemplateId"
          element={<EarlyAccessRequirementTemplateScreen />}
        />
        <Route path="/jurisdictions/:jurisdictionId" element={<JurisdictionScreen />} />
        <Route path="/not-found" element={<NotFoundScreen />} />
        <Route path="*" element={<Navigate replace to="/not-found" />} />
      </Routes>
      {enableStepCodeRoute && (
        <Routes>
          <Route path="/applications/:permitApplicationId/edit/step-code" element={<StepCodeForm />} />
        </Routes>
      )}
    </>
  );
});
