import { Box, Button, Heading, Text } from '@chakra-ui/react';
import React, { useState } from 'react';
import { useParams } from 'react-router-dom';

type ApiReply = {
  message: string;
  id: string;
};

export const InvoiceVersionShowScreen = () => {
  const { id } = useParams();
  const [data, setData] = useState<ApiReply | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const fetchHello = async () => {
    if (!id) return;

    setLoading(true);
    setError(null);

    try {
      const resp = await fetch(`/api/invoice_versions/${id}`, {
        headers: { Accept: 'application/json' },
        credentials: 'include', // keeps cookies/session behavior consistent
      });

      if (!resp.ok) {
        throw new Error(`HTTP ${resp.status}`);
      }

      const json = (await resp.json()) as ApiReply;
      setData(json);
    } catch (e: any) {
      setData(null);
      setError(e?.message ?? 'Request failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Box p="32px">
      <Heading size="lg" mb="8px">
        Invoice Version (POC)
      </Heading>

      <Text mb="16px">
        Route param id: <b>{id}</b>
      </Text>

      <Button onClick={fetchHello} isLoading={loading} loadingText="Calling API...">
        Call hello endpoint
      </Button>

      {data && (
        <Box mt="16px" p="12px" borderWidth="1px" borderRadius="md">
          <Text>
            <b>message:</b> {data.message}
          </Text>
          <Text>
            <b>id:</b> {data.id}
          </Text>
        </Box>
      )}

      {error && (
        <Box mt="16px" p="12px" borderWidth="1px" borderRadius="md">
          <Text>
            <b>Error:</b> {error}
          </Text>
        </Box>
      )}
    </Box>
  );
};

