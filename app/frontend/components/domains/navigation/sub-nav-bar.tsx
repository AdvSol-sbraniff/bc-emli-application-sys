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
      <Container minW="container.lg" px={8} {...breadCrumbContainerProps}>
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
    const invoiceIdForRevisionRequests = searchParams.get('invoice_id') || '';
    const validationRulesUpgradeTypeId = searchParams.get('invoice_upgrade_type_id') || '';
    const validationRulesMode = searchParams.get('mode') || '';
    const revisionRequestsHref = invoiceIdForRevisionRequests
      ? `/revision-requests-admin?invoice_id=${encodeURIComponent(invoiceIdForRevisionRequests)}`
      : '/revision-requests-admin';

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
      '/reports-volume-value': [
        { href: '/invoices-admin', title: t('home.invoicesAdminTitle') },
        { href: '/reports-volume-value', title: 'Reports - Volume and Value' },
      ],
      '/validation-rules-admin': [{ href: '/validation-rules-admin', title: 'Validation Rules Portal' }],
      '/validation-rules-config': [
        { href: '/validation-rules-admin', title: 'Validation Rules Portal' },
        { href: '/validation-rules-config', title: 'Validation Prompt Config' },
      ],
      '/supporting-document-types-admin': [
        { href: '/validation-rules-admin', title: 'Validation Rules Portal' },
        { href: '/supporting-document-types-admin', title: 'Supporting Document Types' },
      ],
      '/supporting-document-type-fields-admin': [
        { href: '/validation-rules-admin', title: 'Validation Rules Portal' },
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
      '/eligibilitycodes-admin': [{ href: '/eligibilitycodes-admin', title: t('home.eligibilityAdminTitle') }],
      '/users-admin': [{ href: '/users-admin', title: t('home.usersAdminTitle') }],
      '/revision-requests-admin': [
        { href: '/invoices-admin', title: t('home.invoicesAdminTitle') },
        { href: '/revision-requests-admin', title: 'Revision Requests Admin' },
      ],
      '/invoice-versions-admin': [
        { href: '/invoices-admin', title: t('home.invoicesAdminTitle') },
        { href: '/invoice-versions-admin', title: 'Versions History Inspection' },
      ],
      '/ai-admin': [
        { href: '/invoices-admin', title: t('home.invoicesAdminTitle') },
        { href: '/ai-admin', title: 'OCR & GenAI' },
      ],
      '/hello-ai-admin': [
        { href: '/invoices-admin', title: t('home.invoicesAdminTitle') },
        { href: '/hello-ai-admin', title: 'Hello AI' },
      ],
      '/upload-invoice-admin': [
        { href: '/invoices-admin', title: t('home.invoicesAdminTitle') },
        { href: '/upload-invoice-admin', title: 'Upload New Invoice' },
      ],
      '/upload-invoice-fix-admin': [
        { href: '/invoices-admin', title: t('home.invoicesAdminTitle') },
        { href: '/upload-invoice-fix-admin', title: 'Upload Invoice Fix' },
      ],
      '/invoice-supporting-documents-admin': [
        { href: '/invoices-admin', title: t('home.invoicesAdminTitle') },
        { href: '/invoice-supporting-documents-admin', title: 'Invoice Supporting Documents' },
      ],
      '/submission-simulator-admin': [
        { href: '/invoices-admin', title: t('home.invoicesAdminTitle') },
        { href: '/submission-simulator-admin', title: 'Contractor Draft Simulator' },
      ],
      '/contractor/upload-invoices': [
        { href: '/ai-contractor-dashboard', title: 'AI contractor portal' },
        { href: '/contractor/upload-invoices', title: 'Upload Invoice(s)' },
      ],
      '/eligibilitycode-editor': [
        { href: '/eligibilitycodes-admin', title: t('home.eligibilityAdminTitle') },
        { href: '/eligibilitycode-editor', title: 'Eligibility code editor' },
      ],
      '/user-editor': [
        { href: '/users-admin', title: t('home.usersAdminTitle') },
        { href: '/user-editor', title: 'User editor' },
      ],
      '/revision-request-editor': [
        { href: '/invoices-admin', title: t('home.invoicesAdminTitle') },
        { href: revisionRequestsHref, title: 'Revision Requests Admin' },
        { href: '/revision-request-editor', title: 'Revision Request Editor' },
      ],
    };

    if (path === '/validation-rules-admin' && validationRulesUpgradeTypeId && validationRulesMode) {
      const recordType = searchParams.get('record_type') || '';
      const recordId = searchParams.get('record_id') || '';
      setIncludeHome(false);
      setBreadcrumbs([
        { href: '/validation-rules-admin', title: 'Validation Rules Portal' },
        {
          href: `/validation-rules-admin?invoice_upgrade_type_id=${encodeURIComponent(validationRulesUpgradeTypeId)}`,
          title: 'Validation Rules Editor',
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
        { href: '/validation-rules-admin', title: 'Validation Rules Portal' },
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
        { href: '/validation-rules-admin', title: 'Validation Rules Portal' },
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
        { href: '/validation-rules-admin', title: 'Validation Rules Portal' },
        {
          href: `/validation-rules-admin?invoice_upgrade_type_id=${encodeURIComponent(validationRulesUpgradeTypeId)}`,
          title: 'Validation Rules Editor',
        },
      ]);
      return;
    }

    if (claimsBreadcrumbs[path]) {
      setIncludeHome(false);
      setBreadcrumbs(claimsBreadcrumbs[path]);
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
              <Text fontWeight="bold">{breadcrumb.title}</Text>
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
