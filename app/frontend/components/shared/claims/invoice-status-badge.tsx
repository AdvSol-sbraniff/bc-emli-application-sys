import { Badge, Tooltip } from '@chakra-ui/react';
import React from 'react';
import { invoiceStatusVisual } from './invoice-status-copy';

type InvoiceStatusBadgeProps = {
  label: string;
  status: string;
  tooltip: string;
  fontSize?: string;
};

export const InvoiceStatusBadge = ({ label, status, tooltip, fontSize = 'sm' }: InvoiceStatusBadgeProps) => {
  const visual = invoiceStatusVisual(status);

  return (
    <Tooltip label={tooltip} hasArrow>
      <Badge
        px={2}
        py={1}
        fontSize={fontSize}
        color={visual.color}
        bg={visual.background}
        borderWidth="1px"
        borderColor={visual.border}
        borderRadius="md"
        fontWeight="bold"
        textTransform="uppercase"
        whiteSpace="nowrap"
        maxW="100%"
        overflow="hidden"
        textOverflow="ellipsis"
        aria-label={`Invoice status: ${label}`}
      >
        {label}
      </Badge>
    </Tooltip>
  );
};
