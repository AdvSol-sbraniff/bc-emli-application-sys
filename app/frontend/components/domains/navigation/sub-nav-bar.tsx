import { Breadcrumb, BreadcrumbItem, BreadcrumbLink, Container, Flex, FlexProps, Text } from '@chakra-ui/react';
import { observer } from 'mobx-react-lite';
import React, { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useLocation } from 'react-router-dom';
import { useMst } from '../../../setup/root';
import { isUUID, toCamelCase } from '../../../utils/utility-functions';
import { RouterLinkButton } from '../../shared/navigation/router-link-button';

export type TBreadcrumbSegment = { href: string; title: string };

interface ISubNavBar extends FlexProps {
  breadCrumbContainerProps?: FlexProps;
  staticBreadCrumbs?: TBreadcrumbSegment[];
}

export const SubNavBar = observer(({ staticBreadCrumbs, breadCrumbContainerProps, ...containerProps }: ISubNavBar) => {
  const location = useLocation();
  const path = location.pathname;
  const [pdfViewerChromeHidden, setPdfViewerChromeHidden] = useState(false);

  useEffect(() => {
    const syncPdfViewerChrome = () => {
      setPdfViewerChromeHidden(document.body.dataset.claimsAiPdfViewerChromeHidden === 'true');
    };

    syncPdfViewerChrome();
    window.addEventListener('claims-ai-pdf-viewer-chrome-change', syncPdfViewerChrome);
    return () => window.removeEventListener('claims-ai-pdf-viewer-chrome-change', syncPdfViewerChrome);
  }, []);

  if (pdfViewerChromeHidden) return null;

  return (
    <Flex
      w="full"
      align="center"
      position="sticky"
      zIndex={9}
      borderBottom="1px solid"
      borderColor="border.light"
      overflow="hidden"
      {...containerProps}
    >
      <Container maxW="full" w="full" px={8} {...breadCrumbContainerProps}>
        {Array.isArray(staticBreadCrumbs) ? (
          <SiteBreadcrumbs breadcrumbs={staticBreadCrumbs} />
        ) : (
          <DynamicBreadcrumb path={path} />
        )}
      </Container>
    </Flex>
  );
});

interface IDynamicBreadcrumbProps {
  path: string;
}

const DynamicBreadcrumb = observer(({ path }: IDynamicBreadcrumbProps) => {
  const { t } = useTranslation();
  const rootStore = useMst();
  const location = useLocation();

  const [breadcrumbs, setBreadcrumbs] = useState<TBreadcrumbSegment[]>([]);
  const [includeHome, setIncludeHome] = useState(true);

  const FRIENDLY_SLUG_RESOURCES = ['jurisdictions'];

  useEffect(() => {
    const searchParams = new URLSearchParams(location.search);
    const validationRulesUpgradeTypeId = searchParams.get('invoice_upgrade_type_id') || '';
    const validationRulesMode = searchParams.get('mode') || '';

    const isInvoicePdfViewerPath =
      /^\/contractor\/sessions\/[^/]+\/invoices\/[^/]+\/messages$/.test(path) ||
      /^\/contractor\/sessions\/[^/]+\/invoices\/[^/]+\/review$/.test(path) ||
      /^\/invoices\/[^/]+\/review$/.test(path) ||
      /^\/invoice-versions\/[^/]+\/review$/.test(path) ||
      /^\/sessions\/[^/]+\/invoices\/[^/]+\/read$/.test(path) ||
      /^\/invoice-versions\/[^/]+$/.test(path) ||
      /^\/invoice-versions-by-version\/[^/]+\/read$/.test(path);

    const claimsBreadcrumbs: Record<string, TBreadcrumbSegment[]> = {
      '/invoices-admin': [{ href: '/invoices-admin', title: t('home.invoicesAdminTitle') }],
      '/ingest-runs-admin': [{ href: '/ingest-runs-admin', title: 'Ingest Runs' }],
      '/claims-rbac-admin': [{ href: '/claims-rbac-admin', title: 'Role Based Access Control' }],
      '/reports-volume-value': [
        { href: '/invoices-admin', title: t('home.invoicesAdminTitle') },
        { href: '/reports-volume-value', title: 'Volume and Value Report' },
      ],
      '/reports-rule-improvement': [{ href: '/reports-rule-improvement', title: 'Rule Improvement Report' }],
      '/validation-rules-admin': [{ href: '/validation-rules-admin', title: 'Fields and Advice Editor' }],
      '/validation-rules-alphabetic-admin': [
        { href: '/validation-rules-alphabetic-admin', title: 'Advice Checks at a Glance' },
      ],
      '/validation-fields-alphabetic-admin': [
        { href: '/validation-fields-alphabetic-admin', title: 'GenAI Fields at a Glance' },
      ],
      '/validation-rules-config': [{ href: '/validation-rules-config', title: 'System Config' }],
      '/test-harness/suites': [{ href: '/test-harness/suites', title: 'Test Suites' }],
      '/test-harness/model-comparisons': [{ href: '/test-harness/model-comparisons', title: 'Model Comparison Runs' }],
      '/test-harness/model-comparisons/new': [
        { href: '/test-harness/model-comparisons', title: 'Model Comparison Runs' },
        { href: '/test-harness/model-comparisons/new', title: 'New Model Comparison' },
      ],
      '/test-harness/rule-comparisons': [{ href: '/test-harness/rule-comparisons', title: 'Rule Comparison Runs' }],
      '/test-harness/rule-comparisons/new': [
        { href: '/test-harness/rule-comparisons', title: 'Rule Comparison Runs' },
        { href: '/test-harness/rule-comparisons/new', title: 'New Rule Comparison' },
      ],
      '/test-harness/regressions': [{ href: '/test-harness/regressions', title: 'Regression Runs' }],
      '/test-harness/regressions/new': [
        { href: '/test-harness/regressions', title: 'Regression Runs' },
        { href: '/test-harness/regressions/new', title: 'New Regression Run' },
      ],
      '/supporting-document-types-admin': [
        { href: '/validation-rules-admin', title: 'Fields and Advice Editor' },
        { href: '/supporting-document-types-admin', title: 'Supporting Document Types' },
      ],
      '/supporting-document-type-fields-admin': [
        { href: '/validation-rules-admin', title: 'Fields and Advice Editor' },
        { href: '/supporting-document-types-admin', title: 'Supporting Document Types' },
        { href: '/supporting-document-type-fields-admin', title: 'Located Fields' },
      ],
      '/downloads-admin': [{ href: '/downloads-admin', title: 'Downloads' }],
      '/heat-pump-product-list-admin': [
        { href: '/downloads-admin', title: 'Downloads' },
        { href: '/heat-pump-product-list-admin', title: 'AHRI heat pump product list config' },
      ],
      '/hpwh-product-list-admin': [
        { href: '/downloads-admin', title: 'Downloads' },
        { href: '/hpwh-product-list-admin', title: 'NEEA HPWH product list config' },
      ],
      '/awhp-product-list-admin': [
        { href: '/downloads-admin', title: 'Downloads' },
        { href: '/awhp-product-list-admin', title: 'Air-to-water product list config' },
      ],
      '/ohpa-product-list-admin': [
        { href: '/downloads-admin', title: 'Downloads' },
        { href: '/ohpa-product-list-admin', title: 'OHPA BC product list config' },
      ],
      '/herv-product-list-admin': [
        { href: '/downloads-admin', title: 'Downloads' },
        { href: '/herv-product-list-admin', title: 'HERV ENERGY STAR product list config' },
      ],
      '/vent-fan-product-list-admin': [
        { href: '/downloads-admin', title: 'Downloads' },
        { href: '/vent-fan-product-list-admin', title: 'ENERGY STAR fan product list config' },
      ],
      '/eligibilitycodes-admin': [{ href: '/eligibilitycodes-admin', title: 'Create Test Eligibility Codes' }],
      '/users-admin': [{ href: '/users-admin', title: 'Create Test Users' }],
      '/conversation-messages-admin': [
        { href: '/invoices-admin', title: t('home.invoicesAdminTitle') },
        { href: '/conversation-messages-admin', title: 'Contractor Conversation' },
      ],
      '/invoice-versions-admin': [
        { href: '/invoices-admin', title: t('home.invoicesAdminTitle') },
        { href: '/invoice-versions-admin', title: 'Versions History Inspection' },
      ],
      '/hello-ai-admin': [
        { href: '/invoices-admin', title: t('home.invoicesAdminTitle') },
        { href: '/hello-ai-admin', title: 'Test AI Network Connectivity' },
      ],
      '/contractorfixsimulation': [
        { href: '/invoices-admin', title: t('home.invoicesAdminTitle') },
        { href: '/contractorfixsimulation', title: 'Contractor Fix Simulation' },
      ],
      '/advice-refresh-simulation-admin': [
        { href: '/invoices-admin', title: t('home.invoicesAdminTitle') },
        { href: '/advice-refresh-simulation-admin', title: 'Refresh AI Advice' },
      ],
      '/invoice-supporting-documents-admin': [
        { href: '/invoices-admin', title: t('home.invoicesAdminTitle') },
        { href: '/invoice-supporting-documents-admin', title: 'Invoice Supporting Documents' },
      ],
      '/submission-simulator-admin': [
        { href: '/invoices-admin', title: t('home.invoicesAdminTitle') },
        { href: '/submission-simulator-admin', title: 'Contractor Simulator' },
      ],
      '/contractor/upload-invoices': [
        { href: '/ai-contractor-dashboard', title: 'AI contractor portal' },
        { href: '/contractor/upload-invoices', title: 'Upload Invoice' },
      ],
      '/eligibilitycode-editor': [
        { href: '/eligibilitycodes-admin', title: 'Create Test Eligibility Codes' },
        { href: '/eligibilitycode-editor', title: 'Eligibility code editor' },
      ],
      '/contractors-admin': [{ href: '/contractors-admin', title: 'Create Test Contractors' }],
      '/user-editor': [
        { href: '/users-admin', title: 'Create Test Users' },
        { href: '/user-editor', title: 'User editor' },
      ],
    };

    if (path === '/validation-rules-admin' && validationRulesUpgradeTypeId && validationRulesMode) {
      const recordType = searchParams.get('record_type') || '';
      const recordId = searchParams.get('record_id') || '';
      setIncludeHome(false);
      setBreadcrumbs([
        { href: '/validation-rules-admin', title: 'Fields and Advice Editor' },
        {
          href: `/validation-rules-admin?invoice_upgrade_type_id=${encodeURIComponent(validationRulesUpgradeTypeId)}`,
          title: 'Fields and Advice Editor',
        },
        {
          href: `/validation-rules-admin?invoice_upgrade_type_id=${encodeURIComponent(validationRulesUpgradeTypeId)}&mode=${encodeURIComponent(validationRulesMode)}${recordType ? `&record_type=${encodeURIComponent(recordType)}` : ''}${recordId ? `&record_id=${encodeURIComponent(recordId)}` : ''}`,
          title: validationRulesMode === 'create' ? 'Add Validation Record' : 'Edit Validation Record',
        },
      ]);
      return;
    }

    if (path === '/supporting-document-types-admin' && validationRulesMode) {
      const recordId = searchParams.get('id') || '';
      setIncludeHome(false);
      setBreadcrumbs([
        { href: '/validation-rules-admin', title: 'Fields and Advice Editor' },
        {
          href: '/supporting-document-types-admin',
          title: 'Supporting Document Types',
        },
        {
          href: `/supporting-document-types-admin?mode=${encodeURIComponent(validationRulesMode)}${recordId ? `&id=${encodeURIComponent(recordId)}` : ''}`,
          title: validationRulesMode === 'create' ? 'Add Supporting Document Type' : 'Edit Supporting Document Type',
        },
      ]);
      return;
    }

    if (path === '/supporting-document-type-fields-admin' && validationRulesMode) {
      const typeId = searchParams.get('type_id') || '';
      const recordId = searchParams.get('id') || '';
      setIncludeHome(false);
      setBreadcrumbs([
        { href: '/validation-rules-admin', title: 'Fields and Advice Editor' },
        { href: '/supporting-document-types-admin', title: 'Supporting Document Types' },
        {
          href: `/supporting-document-type-fields-admin${typeId ? `?type_id=${encodeURIComponent(typeId)}` : ''}`,
          title: 'Located Fields',
        },
        {
          href: `/supporting-document-type-fields-admin?${new URLSearchParams({
            ...(typeId ? { type_id: typeId } : {}),
            mode: validationRulesMode,
            ...(recordId ? { id: recordId } : {}),
          }).toString()}`,
          title: validationRulesMode === 'create' ? 'Add Field' : 'Edit Field',
        },
      ]);
      return;
    }

    if (path === '/validation-rules-admin' && validationRulesUpgradeTypeId) {
      setIncludeHome(false);
      setBreadcrumbs([
        { href: '/validation-rules-admin', title: 'Fields and Advice Editor' },
        {
          href: `/validation-rules-admin?invoice_upgrade_type_id=${encodeURIComponent(validationRulesUpgradeTypeId)}`,
          title: 'Fields and Advice Editor',
        },
      ]);
      return;
    }

    if (claimsBreadcrumbs[path]) {
      setIncludeHome(false);
      setBreadcrumbs(claimsBreadcrumbs[path]);
      return;
    }

    if (/^\/reports-rule-improvement\/[^/]+\/[^/]+$/.test(path)) {
      setIncludeHome(false);
      setBreadcrumbs([
        { href: '/reports-rule-improvement', title: 'Rule Improvement Report' },
        { href: path, title: 'Rule Improvement Detail' },
      ]);
      return;
    }

    if (/^\/test-harness\/suites\/[^/]+\/cases$/.test(path)) {
      setIncludeHome(false);
      setBreadcrumbs([
        { href: '/test-harness/suites', title: 'Test Suites' },
        { href: path, title: 'Test Suite Cases' },
      ]);
      return;
    }

    if (/^\/test-harness\/model-comparisons\/[^/]+(?:\/results)?$/.test(path)) {
      setIncludeHome(false);
      setBreadcrumbs([
        { href: '/test-harness/model-comparisons', title: 'Model Comparison Runs' },
        { href: path, title: 'Model Comparison Results' },
      ]);
      return;
    }

    if (/^\/test-harness\/rule-comparisons\/[^/]+$/.test(path)) {
      setIncludeHome(false);
      setBreadcrumbs([
        { href: '/test-harness/rule-comparisons', title: 'Rule Comparison Runs' },
        { href: path, title: 'Rule Comparison Results' },
      ]);
      return;
    }

    if (/^\/test-harness\/regressions\/[^/]+$/.test(path)) {
      setIncludeHome(false);
      setBreadcrumbs([
        { href: '/test-harness/regressions', title: 'Regression Runs' },
        { href: path, title: 'Regression Run Results' },
      ]);
      return;
    }

    if (isInvoicePdfViewerPath) {
      const isContractorViewer = /^\/contractor\/sessions\/[^/]+\/invoices\/[^/]+\/review$/.test(path);
      const isContractorMessages = /^\/contractor\/sessions\/[^/]+\/invoices\/[^/]+\/messages$/.test(path);
      const isByVersionViewer =
        /^\/invoice-versions\/[^/]+\/review$/.test(path) || /^\/invoice-versions-by-version\/[^/]+\/read$/.test(path);
      setIncludeHome(false);
      setBreadcrumbs(
        isContractorViewer
          ? [
              { href: '/ai-contractor-dashboard', title: 'AI contractor portal' },
              { href: path, title: 'Contractor Invoice Review' },
            ]
          : isContractorMessages
            ? [
                { href: '/ai-contractor-dashboard', title: 'AI contractor portal' },
                {
                  href: `${path.replace(/\/messages$/, '/review')}?source=portal`,
                  title: 'Contractor Invoice Review',
                },
                { href: path, title: 'Messages & Requested Changes' },
              ]
            : [
                { href: '/invoices-admin', title: t('home.invoicesAdminTitle') },
                {
                  href: path,
                  title: isByVersionViewer ? 'Invoice Version Snapshot' : 'Invoice Review - Current Version',
                },
              ],
      );
      return;
    }

    setIncludeHome(true);

    // Get the current path and split into segments
    const pathSegments = path.split('/').filter(Boolean);

    const breadcrumbSegments = pathSegments
      .filter((segment, index) => {
        const previousSegment = pathSegments[index - 1];
        const resourceNeeded = isUUID(segment) || FRIENDLY_SLUG_RESOURCES.includes(previousSegment);
        return !isUUID(segment) && !resourceNeeded;
      })
      .map((segment) => {
        const segmentIndex = pathSegments.indexOf(segment);
        const href = '/' + pathSegments.slice(0, segmentIndex + 1).join('/');
        const previousSegment = pathSegments[segmentIndex - 1];
        const resourceNeeded = FRIENDLY_SLUG_RESOURCES.includes(previousSegment);

        const currentResourceMap = {
          jurisdictions: rootStore.jurisdictionStore.currentJurisdiction?.name,
          'permit-applications': rootStore.permitApplicationStore.currentPermitApplication?.number,
        };

        const titleGot = resourceNeeded
          ? currentResourceMap[previousSegment] || segment
          : // @ts-ignore
            t(`site.breadcrumb.${toCamelCase(segment)}`);

        const title = decodeURIComponent(titleGot);

        return { href, title };
      });

    setBreadcrumbs(breadcrumbSegments);
  }, [path, location.search, rootStore.jurisdictionStore.currentJurisdiction]);

  return <SiteBreadcrumbs breadcrumbs={breadcrumbs} includeHome={includeHome} />;
});

interface ISiteBreadcrumbProps {
  breadcrumbs: TBreadcrumbSegment[];
  includeHome?: boolean;
}

const SiteBreadcrumbs = observer(function SiteBreadcrumb({ breadcrumbs, includeHome = true }: ISiteBreadcrumbProps) {
  const { t } = useTranslation();
  return (
    <Breadcrumb spacing={2} separator="/">
      {includeHome && (
        <BreadcrumbItem>
          <BreadcrumbLink as={RouterLinkButton} to="/" textTransform="capitalize" variant="link">
            {t('site.home')}
          </BreadcrumbLink>
        </BreadcrumbItem>
      )}

      {breadcrumbs.map((breadcrumb, index) => {
        const finalSegment = index == breadcrumbs.length - 1;
        return (
          <BreadcrumbItem key={index}>
            {finalSegment ? (
              <Text fontWeight="normal">{breadcrumb.title}</Text>
            ) : (
              <BreadcrumbLink as={RouterLinkButton} to={breadcrumb.href} variant="link">
                {breadcrumb.title}
              </BreadcrumbLink>
            )}
          </BreadcrumbItem>
        );
      })}
    </Breadcrumb>
  );
});
