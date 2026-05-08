import React, { useState } from 'react';
import { Box, Button, Container, Flex, Heading, Spinner, Text, Textarea } from '@chakra-ui/react';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';

type HelloAiResponse = {
  message?: string;
  error?: string;
  ok?: boolean;
};

export default function HelloAiAdminScreen() {
  const [prompt, setPrompt] = useState('Hello there. Please say hello back in one short sentence.');
  const [reply, setReply] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleSend = async () => {
    const cleanPrompt = prompt.trim();
    if (!cleanPrompt) {
      setError('Enter a prompt first.');
      setReply('');
      return;
    }

    setLoading(true);
    setError('');

    try {
      const res = await fetch('/api/claims/admin/hello_ai', {
        method: 'POST',
        headers: {
          Accept: 'application/json',
          'Content-Type': 'application/json',
        },
        credentials: 'include',
        body: JSON.stringify({ prompt: cleanPrompt }),
      });

      const data: HelloAiResponse = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);

      setReply(String(data?.message || '').trim());
    } catch (e: any) {
      setReply('');
      setError(e?.message || 'Simple chat failed.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Hello AI" />

      <Container maxW="container.lg" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Heading size="md" mb={2}>
            Simple chat smoke test
          </Heading>
          <Text fontSize="sm" opacity={0.8} mb={4}>
            Type one short user prompt, send it to the configured assistant, and inspect the raw reply.
          </Text>

          <Textarea
            value={prompt}
            onChange={(e) => setPrompt(e.target.value)}
            minH="160px"
            resize="vertical"
            placeholder="Type a short hello-world style prompt here"
            mb={4}
          />

          <Flex align="center" gap={3} mb={4}>
            <Button colorScheme="blue" onClick={handleSend} isLoading={loading} loadingText="Sending...">
              Send
            </Button>
            {loading ? <Spinner size="sm" /> : null}
          </Flex>

          {error ? (
            <Box p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md" mb={4}>
              <Text fontSize="sm" color="red.700">
                {error}
              </Text>
            </Box>
          ) : null}

          <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={4} bg="gray.50">
            <Text fontSize="xs" opacity={0.7} mb={1}>
              Assistant reply
            </Text>
            <Text whiteSpace="pre-wrap" fontSize="sm">
              {reply || 'No reply yet.'}
            </Text>
          </Box>
        </Box>
      </Container>
    </Flex>
  );
}
