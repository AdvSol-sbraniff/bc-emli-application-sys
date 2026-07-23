import { Box, BoxProps, Container, ContainerProps, Flex, Heading } from '@chakra-ui/react';
import React from 'react';

interface IThinBlueTitleBarProps extends BoxProps {
  title: string;
  leftElement?: React.ReactNode;
  rightElement?: React.ReactNode;
  contentMaxW?: ContainerProps['maxW'];
}

export const ThinBlueTitleBar = ({
  title,
  leftElement,
  rightElement,
  contentMaxW = 'container.lg',
  ...rest
}: IThinBlueTitleBarProps) => {
  return (
    <Box h="fit-content" bg="theme.blueGradient" {...rest}>
      <Container
        as={Flex}
        justifyContent="space-between"
        alignItems="center"
        gap={4}
        flexWrap="wrap"
        maxW={contentMaxW}
        minHeight="96px"
      >
        <Flex alignItems="center" gap={4}>
          {leftElement ? <Box flexShrink={0}>{leftElement}</Box> : null}
          <Heading as="h1" color="greys.white" fontSize="1.75rem">
            {title}
          </Heading>
        </Flex>
        {rightElement ? <Box flexShrink={0}>{rightElement}</Box> : null}
      </Container>
    </Box>
  );
};
