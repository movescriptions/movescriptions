'use client';
import { useEffect, useState } from 'react'

import Typography from '@mui/material/Typography';
import Box from '@mui/material/Box';
import Card from '@mui/material/Card';
import CardContent from '@mui/material/CardContent';
import Grid from '@mui/material/Grid';
import Snackbar from '@mui/material/Snackbar';
import Alert from '@mui/material/Alert';
import CircularProgress from '@mui/material/CircularProgress';
import Button from '@mui/material/Button';

import { Movescription } from '@/types'
import { movescriptionConfig } from '@/config/movescription'
import { IndexerStateID, GlobalStateFilterView } from '@roochnetwork/rooch-sdk'
import { useRoochClient } from '@roochnetwork/rooch-sdk-kit'

const itemsPerPage = 20;

export type UserAssetsProps = {
  address: string,
}

export default function UserAssets(props: UserAssetsProps) {
  const [error, setError] = useState<Error | null>(null);
  const [isPending, setPending] = useState<boolean>(false);
  const [items, setItems] = useState<Array<Movescription>>([]);

  const filter: GlobalStateFilterView = {
    object_type_with_owner: {
      object_type: `${movescriptionConfig.movescriptionAddress}::movescription::Movescription`,
      owner: props.address,
    }
  };
  const [nextCursor, setNextCursor] = useState<IndexerStateID | null>(null);
  const [hasMore, setHasMore] = useState<boolean>(true);

  const roochClient = useRoochClient()

  const handleLoadMore = async () => {
    setPending(true);

    console.log("handleLoadMore filter:", filter);

    try {
      const newData = await roochClient.queryGlobalStates({
        filter: filter,
        cursor: nextCursor,
        limit: itemsPerPage,
      })

      console.log("handleLoadMore result:", newData);

      const newItems = new Array<Movescription>();
      for (const state of newData.data) {
        items.push({
          object_id: `${state.object_id}`,
          tick: "MOVE",
          value: 925,
        })
      }

      setItems([...items, ...newItems]);
      setNextCursor(newData.next_cursor);
      setHasMore(newData.has_next_page);
    } catch (e: any) {
      console.error(e)
      setError(e)

      setTimeout(()=>{
        setError(null)
      }, 6000)
    } finally {
      setPending(false)
    }
  };

  useEffect(() => {
    handleLoadMore()
  }, [])

  return (
    <Box sx={{ maxWidth: 'lg' }}>
      <Grid container spacing={2}>
        {items.length>0 ? items.map((item) => (
            <Grid item xs={12} sm={6} md={4} lg={3} key={item.object_id}>
              <Card style={{ width: '100%', height: '120px' }}>
                <CardContent>
                  <Typography variant="h5" component="div">
                    {item.tick}({item.object_id})
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    {item.value}
                  </Typography>
                </CardContent>
              </Card>
            </Grid>
        )):(
          <Typography>No Inscription</Typography>
        )}
      </Grid>

      {isPending && (
        <CircularProgress></CircularProgress>
      )}

      <Snackbar open={error != null} autoHideDuration={6000}>
        <Alert severity="error">
          {error?.message}
        </Alert>
      </Snackbar>

      {hasMore && (
        <Button onClick={handleLoadMore}>Load More</Button>
      )}
    </Box>
  );
}
