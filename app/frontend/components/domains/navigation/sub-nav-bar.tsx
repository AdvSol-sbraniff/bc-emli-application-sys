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
    const revisionRequestsHref = invoiceIdForRevisionRequests
      ? `/revision-requests-admin?invoice_id=${encodeURIComponent(invoiceIdForRevisionRequests)}`
      : '/revision-requests-admin';

    const isInvoicePdfViewerPath =
      /^\/sessions\/[^/]+\/invoices\/[^/]+\/read$/.test(path) || /^\/invoice-versions\/[^/]+$/.test(path);

    const claimsBreadcrumbs: Record<string, TBreadcrumbSegment[]> = {
      '/invoices-admin': [{ href: '/invoices-admin', title: t('home.invoicesAdminTitle') }],
      '/sessions-admin': [{ href: '/sessions-admin', title: t('home.sessionsAdminTitle') }],
      '/rulesets-admin': [{ href: '/rulesets-admin', title: t('home.rulesetsAdminTitle') }],
      '/eligibilitycodes-admin': [{ href: '/eligibilitycodes-admin', title: t('home.eligibilityAdminTitle') }],
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
      '/upload-invoice-admin': [
        { href: '/invoices-admin', title: t('home.invoicesAdminTitle') },
        { href: '/upload-invoice-admin', title: 'Upload New Invoice' },
      ],
      '/upload-invoice-fix-admin': [
        { href: '/invoices-admin', title: t('home.invoicesAdminTitle') },
        { href: '/upload-invoice-fix-admin', title: 'Upload Invoice Fix' },
      ],
      '/ruleset-editor': [
        { href: '/rulesets-admin', title: t('home.rulesetsAdminTitle') },
        { href: '/ruleset-editor', title: 'Ruleset editor' },
      ],
      '/eligibilitycode-editor': [
        { href: '/eligibilitycodes-admin', title: t('home.eligibilityAdminTitle') },
        { href: '/eligibilitycode-editor', title: 'Eligibility code editor' },
      ],
      '/admin-create-session': [
        { href: '/sessions-admin', title: t('home.sessionsAdminTitle') },
        { href: '/admin-create-session', title: 'Create session' },
      ],
      '/revision-request-editor': [
        { href: '/invoices-admin', title: t('home.invoicesAdminTitle') },
        { href: revisionRequestsHref, title: 'Revision Requests Admin' },
        { href: '/revision-request-editor', title: 'Revision Request Editor' },
      ],
    };

    if (claimsBreadcrumbs[path]) {
      setIncludeHome(false);
      setBreadcrumbs(claimsBreadcrumbs[path]);
      return;
    }

    if (isInvoicePdfViewerPath) {
      setIncludeHome(false);
      setBreadcrumbs([
        { href: '/invoices-admin', title: t('home.invoicesAdminTitle') },
        { href: path, title: 'Invoices Admin - PDF Viewer' },
      ]);
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
