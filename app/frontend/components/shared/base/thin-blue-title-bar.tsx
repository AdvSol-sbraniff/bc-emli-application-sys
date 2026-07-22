import { Box, BoxProps, Container, Flex, Heading } from '@chakra-ui/react';
import React from 'react';

interface IThinBlueTitleBarProps extends BoxProps {
  title: string;
  rightElement?: React.ReactNode;
}

export const ThinBlueTitleBar = ({ title, rightElement, ...rest }: IThinBlueTitleBarProps) => {
  return (
    <Box h="fit-content" bg="theme.blueGradient" {...rest}>
      <Container
        as={Flex}
        justifyContent="space-between"
        alignItems="center"
        gap={4}
        flexWrap="wrap"
        maxW="container.lg"
        minHeight="96px"
      >
        <Heading as="h1" color="greys.white" fontSize="1.75rem">
          {title}
        </Heading>
        {rightElement ? <Box flexShrink={0}>{rightElement}</Box> : null}
      </Container>
    </Box>
  );
};
