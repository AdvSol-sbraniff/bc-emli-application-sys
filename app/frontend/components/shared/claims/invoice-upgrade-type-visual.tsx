import React from 'react';
import { Box, Flex, Text } from '@chakra-ui/react';

export type InvoiceUpgradeTypeKey =
  | 'common'
  | 'air_source_heat_pump_electric'
  | 'air_source_heat_pump_gas_propane'
  | 'air_source_heat_pump_oil'
  | 'air_source_heat_pump_wood'
  | 'air_to_water_heat_pump'
  | 'combined_space_water_heat_pump'
  | 'dual_fuel_ducted_heat_pump'
  | 'electrical_service_upgrade'
  | 'health_and_safety_remediation'
  | 'heat_pump_water_heater'
  | 'insulation'
  | 'ventilation'
  | 'windows_doors';

export type InvoiceUpgradeTypeMeta = {
  accent: string;
  bg: string;
  border: string;
  key: InvoiceUpgradeTypeKey;
  label: string;
  permitClassificationCode?: string;
  shortLabel: string;
};

const INVOICE_UPGRADE_TYPE_META: Record<InvoiceUpgradeTypeKey, InvoiceUpgradeTypeMeta> = {
  common: {
    key: 'common',
    label: 'Common invoice evidence',
    shortLabel: 'CO',
    accent: '#4A5568',
    bg: '#EDF2F7',
    border: '#CBD5E0',
  },
  air_source_heat_pump_electric: {
    key: 'air_source_heat_pump_electric',
    label: 'ASHP - electric',
    shortLabel: 'AE',
    permitClassificationCode: 'invoice_heat_pump_space',
    accent: '#2B6CB0',
    bg: '#EBF8FF',
    border: '#90CDF4',
  },
  air_source_heat_pump_wood: {
    key: 'air_source_heat_pump_wood',
    label: 'ASHP - wood',
    shortLabel: 'AW',
    permitClassificationCode: 'invoice_heat_pump_space',
    accent: '#2F855A',
    bg: '#F0FFF4',
    border: '#9AE6B4',
  },
  air_source_heat_pump_gas_propane: {
    key: 'air_source_heat_pump_gas_propane',
    label: 'ASHP - gas/propane',
    shortLabel: 'AG',
    permitClassificationCode: 'invoice_heat_pump_space',
    accent: '#DD6B20',
    bg: '#FFFAF0',
    border: '#FBD38D',
  },
  air_source_heat_pump_oil: {
    key: 'air_source_heat_pump_oil',
    label: 'ASHP - oil',
    shortLabel: 'AO',
    permitClassificationCode: 'invoice_heat_pump_space',
    accent: '#744210',
    bg: '#FFFFF0',
    border: '#F6E05E',
  },
  dual_fuel_ducted_heat_pump: {
    key: 'dual_fuel_ducted_heat_pump',
    label: 'Dual fuel ducted HP',
    shortLabel: 'DF',
    permitClassificationCode: 'invoice_heat_pump_space',
    accent: '#805AD5',
    bg: '#FAF5FF',
    border: '#D6BCFA',
  },
  air_to_water_heat_pump: {
    key: 'air_to_water_heat_pump',
    label: 'Air-to-water HP',
    shortLabel: 'AT',
    permitClassificationCode: 'invoice_heat_pump_space',
    accent: '#2C7A7B',
    bg: '#E6FFFA',
    border: '#81E6D9',
  },
  combined_space_water_heat_pump: {
    key: 'combined_space_water_heat_pump',
    label: 'Combined space/water HP',
    shortLabel: 'CW',
    permitClassificationCode: 'invoice_heat_pump_space',
    accent: '#285E61',
    bg: '#E6FFFA',
    border: '#4FD1C5',
  },
  heat_pump_water_heater: {
    key: 'heat_pump_water_heater',
    label: 'Heat pump water heater',
    shortLabel: 'HW',
    permitClassificationCode: 'invoice_heat_pump_water',
    accent: '#2C7A7B',
    bg: '#E6FFFA',
    border: '#81E6D9',
  },
  electrical_service_upgrade: {
    key: 'electrical_service_upgrade',
    label: 'Electrical service upgrade',
    shortLabel: 'ES',
    permitClassificationCode: 'invoice_electrical_upgrade',
    accent: '#B7791F',
    bg: '#FFFAEB',
    border: '#F6E05E',
  },
  insulation: {
    key: 'insulation',
    label: 'Insulation',
    shortLabel: 'IN',
    permitClassificationCode: 'invoice_insulation',
    accent: '#6B46C1',
    bg: '#FAF5FF',
    border: '#D6BCFA',
  },
  ventilation: {
    key: 'ventilation',
    label: 'Ventilation',
    shortLabel: 'VE',
    permitClassificationCode: 'invoice_ventilation',
    accent: '#0F766E',
    bg: '#F0FDFA',
    border: '#99F6E4',
  },
  windows_doors: {
    key: 'windows_doors',
    label: 'Windows and doors',
    shortLabel: 'WD',
    permitClassificationCode: 'invoice_windows_doors',
    accent: '#1A365D',
    bg: '#F7FAFC',
    border: '#BEE3F8',
  },
  health_and_safety_remediation: {
    key: 'health_and_safety_remediation',
    label: 'Health and safety remediation',
    shortLabel: 'HS',
    permitClassificationCode: 'invoice_health_safety',
    accent: '#C53030',
    bg: '#FFF5F5',
    border: '#FEB2B2',
  },
};

export const INVOICE_UPGRADE_TYPE_FILTER_ORDER: InvoiceUpgradeTypeKey[] = [
  'air_source_heat_pump_electric',
  'air_source_heat_pump_wood',
  'air_source_heat_pump_gas_propane',
  'air_source_heat_pump_oil',
  'dual_fuel_ducted_heat_pump',
  'air_to_water_heat_pump',
  'combined_space_water_heat_pump',
  'heat_pump_water_heater',
  'electrical_service_upgrade',
  'insulation',
  'windows_doors',
  'ventilation',
  'health_and_safety_remediation',
];

const FALLBACK_META: InvoiceUpgradeTypeMeta = {
  key: 'common',
  label: 'Unknown upgrade type',
  shortLabel: 'UN',
  accent: '#4A5568',
  bg: '#F7FAFC',
  border: '#CBD5E0',
};

export function getInvoiceUpgradeTypeMeta(
  upgradeTypeKey?: string | null,
  description?: string | null,
): InvoiceUpgradeTypeMeta {
  const typedKey = upgradeTypeKey as InvoiceUpgradeTypeKey | undefined;
  if (typedKey && INVOICE_UPGRADE_TYPE_META[typedKey]) {
    return INVOICE_UPGRADE_TYPE_META[typedKey];
  }

  return {
    ...FALLBACK_META,
    key: 'common',
    label: description || upgradeTypeKey || FALLBACK_META.label,
    shortLabel:
      (upgradeTypeKey || 'UN')
        .replace(/[^A-Za-z0-9]/g, '')
        .slice(0, 2)
        .toUpperCase() || 'UN',
  };
}

type TileProps = {
  description?: string | null;
  size?: number;
  upgradeTypeKey?: string | null;
};

export function InvoiceUpgradeTypeTile({ description, size = 38, upgradeTypeKey }: TileProps) {
  const meta = getInvoiceUpgradeTypeMeta(upgradeTypeKey, description);

  return (
    <Flex
      align="center"
      justify="center"
      w={`${size}px`}
      h={`${size}px`}
      borderRadius="12px"
      borderWidth="1px"
      borderColor={meta.border}
      bg={meta.bg}
      boxShadow="sm"
      flexShrink={0}
      overflow="hidden"
    >
      <InvoiceUpgradeGlyph accent={meta.accent} shortLabel={meta.shortLabel} upgradeTypeKey={upgradeTypeKey} />
    </Flex>
  );
}

function InvoiceUpgradeGlyph({
  accent,
  shortLabel,
  upgradeTypeKey,
}: {
  accent: string;
  shortLabel: string;
  upgradeTypeKey?: string | null;
}) {
  const commonProps = {
    fill: 'none',
    stroke: accent,
    strokeLinecap: 'round' as const,
    strokeLinejoin: 'round' as const,
    strokeWidth: 1.8,
  };

  switch (upgradeTypeKey) {
    case 'electrical_service_upgrade':
      return (
        <Box as="svg" viewBox="0 0 24 24" w="22px" h="22px" aria-hidden="true">
          <path {...commonProps} d="M13 2 6.5 13h4.2L9 22l8.5-11H13z" />
        </Box>
      );
    case 'health_and_safety_remediation':
      return (
        <Box as="svg" viewBox="0 0 24 24" w="22px" h="22px" aria-hidden="true">
          <path {...commonProps} d="M12 3l7 3v5c0 5-3.2 8.4-7 10-3.8-1.6-7-5-7-10V6l7-3z" />
          <path {...commonProps} d="M12 8v7" />
          <path {...commonProps} d="M8.5 11.5h7" />
        </Box>
      );
    case 'air_source_heat_pump_electric':
    case 'air_source_heat_pump_gas_propane':
    case 'air_source_heat_pump_oil':
    case 'air_source_heat_pump_wood':
    case 'dual_fuel_ducted_heat_pump':
      return (
        <Box as="svg" viewBox="0 0 24 24" w="22px" h="22px" aria-hidden="true">
          <circle {...commonProps} cx="12" cy="12" r="2.2" />
          <path {...commonProps} d="M12 4c2.2 0 4 1.8 4 4-2.4.2-4.4-.4-6.1-2.1C9.9 4.9 10.8 4 12 4z" />
          <path {...commonProps} d="M20 12c0 2.2-1.8 4-4 4-.2-2.4.4-4.4 2.1-6.1.9 0 1.9.9 1.9 2.1z" />
          <path {...commonProps} d="M12 20c-2.2 0-4-1.8-4-4 2.4-.2 4.4.4 6.1 2.1 0 1-.9 1.9-2.1 1.9z" />
          <path {...commonProps} d="M4 12c0-2.2 1.8-4 4-4 .2 2.4-.4 4.4-2.1 6.1C4.9 14.1 4 13.2 4 12z" />
        </Box>
      );
    case 'air_to_water_heat_pump':
    case 'combined_space_water_heat_pump':
    case 'heat_pump_water_heater':
      return (
        <Box as="svg" viewBox="0 0 24 24" w="22px" h="22px" aria-hidden="true">
          <path {...commonProps} d="M12 3.5C8.9 7.1 7.4 9.5 7.4 12a4.6 4.6 0 1 0 9.2 0c0-2.5-1.5-4.9-4.6-8.5z" />
          <path {...commonProps} d="M17.8 7.3c1 .6 1.8 1.7 2 3" />
          <path {...commonProps} d="M18.1 12.2c.1 1-.1 2-.8 2.9" />
        </Box>
      );
    case 'insulation':
      return (
        <Box as="svg" viewBox="0 0 24 24" w="22px" h="22px" aria-hidden="true">
          <rect {...commonProps} x="4" y="6" width="16" height="3.2" rx="1.6" />
          <rect {...commonProps} x="4" y="10.4" width="16" height="3.2" rx="1.6" />
          <rect {...commonProps} x="4" y="14.8" width="16" height="3.2" rx="1.6" />
        </Box>
      );
    case 'ventilation':
      return (
        <Box as="svg" viewBox="0 0 24 24" w="22px" h="22px" aria-hidden="true">
          <path {...commonProps} d="M4 9.5c2.1 0 2.1-2 4.2-2s2.1 2 4.2 2 2.1-2 4.2-2 2.1 2 4.2 2" />
          <path {...commonProps} d="M4 14c2.1 0 2.1-2 4.2-2s2.1 2 4.2 2 2.1-2 4.2-2 2.1 2 4.2 2" />
          <path {...commonProps} d="M4 18.5c2.1 0 2.1-2 4.2-2s2.1 2 4.2 2 2.1-2 4.2-2 2.1 2 4.2 2" />
        </Box>
      );
    case 'windows_doors':
      return (
        <Box as="svg" viewBox="0 0 24 24" w="22px" h="22px" aria-hidden="true">
          <rect {...commonProps} x="4.5" y="4.5" width="15" height="15" rx="1.8" />
          <path {...commonProps} d="M12 4.5v15" />
          <path {...commonProps} d="M4.5 12h15" />
        </Box>
      );
    default:
      return (
        <Flex direction="column" align="center" justify="center" color={accent} lineHeight="1">
          <Text fontSize="11px" fontWeight="bold" letterSpacing="0.08em">
            {shortLabel}
          </Text>
        </Flex>
      );
  }
}
