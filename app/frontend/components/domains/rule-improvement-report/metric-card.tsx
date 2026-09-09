import { Box, HStack, Text } from '@chakra-ui/react';
import React from 'react';

export function MetricCard({
  label,
  value,
  help,
  active,
  onClick,
}: {
  label: string;
  value: string | number;
  help: string;
  active?: boolean;
  onClick?: () => void;
}) {
  return (
    <Box
      as={onClick ? 'button' : 'div'}
      type={onClick ? 'button' : undefined}
      onClick={onClick}
      textAlign="left"
      borderWidth="1px"
      borderColor={active ? 'blue.500' : 'gray.200'}
      borderRadius="md"
      bg={active ? 'blue.50' : 'white'}
      p={4}
      minH="118px"
      width="100%"
      transition="all 0.15s ease"
      _hover={onClick ? { borderColor: 'blue.400', boxShadow: 'sm' } : undefined}
    >
      <HStack justify="space-between" align="start">
        <Text fontSize="sm" fontWeight="semibold" color="gray.700">
          {label}
        </Text>
        <Text fontSize="2xl" lineHeight="1" fontWeight="bold" color="blue.700">
          {value}
        </Text>
      </HStack>
      <Text mt={3} fontSize="xs" color="gray.600">
        {help}
      </Text>
    </Box>
  );
}
