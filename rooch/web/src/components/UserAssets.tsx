'use client';
import { useEffect, useState } from 'react'

import Typography from '@mui/material/Typography';
import Box from '@mui/material/Box';
import Card from '@mui/material/Card';
import CardActions from '@mui/material/CardActions'
import CardContent from '@mui/material/CardContent';
import Grid from '@mui/material/Grid';
import Snackbar from '@mui/material/Snackbar';
import Alert from '@mui/material/Alert';
import CircularProgress from '@mui/material/CircularProgress';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import ButtonGroup from '@mui/material/ButtonGroup';

import { Movescription } from '@/types'
import { movescriptionConfig } from '@/config/movescription'
import { IndexerStateID, GlobalStateFilterView } from '@roochnetwork/rooch-sdk'
import { useRoochClient } from '@roochnetwork/rooch-sdk-kit'

const itemsPerPage = 9;

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
        descending_order: true,
      })

      console.log("handleLoadMore result:", newData);

      const newItems = new Array<Movescription>();
      for (const state of newData.data) {
        newItems.push({
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
    if (!hasMore) {
      return
    }

    console.log("handleLoadMore");

    handleLoadMore()
  }, [props.address])

  return (
    <Box sx={{ maxWidth: 'lg' }}>
      <Grid container spacing={4}>
        {items.length > 0 ? items.map((item) => (
          <Grid item xs={12} sm={6} md={4} key={item.object_id}>
            <Card style={{ padding: '10px' }}>
              <CardContent>
                <div style={{display: 'flex', justifyContent: 'space-between'}}>
                  <Chip label={item.tick} color="primary" size='small'/>
                  <Chip label={'#' + item.object_id.substring(2, 8)} color="secondary" size='small' />
                </div>
                <Typography variant="h5" color="text.secondary" align="center">
                  {item.value}
                </Typography>
              </CardContent>
              <CardActions style={{display: 'flex', justifyContent: 'space-between', flexWrap: 'wrap', gap: '6px'}}>
                <Button variant="outlined" size='small'>Transfer</Button>
                <Button variant="outlined" size='small'>List</Button>
                <Button variant="outlined" size='small'>Split</Button>
                <Button variant="outlined" size='small' color="error">Burn</Button>
              </CardActions>
            </Card>
          </Grid>
        )) : isPending ? (
          <CircularProgress></CircularProgress>
        ) :(
          <Typography>No Inscription</Typography>
        )}
      </Grid>

      
      <Snackbar open={error != null} autoHideDuration={6000}>
        <Alert severity="error">
          {error?.message}
        </Alert>
      </Snackbar>

      <Box style={{display: 'flex', justifyContent: 'center', marginTop: '10px'}}>
        <ButtonGroup variant="contained" aria-label="Basic button group">
          {!isPending && hasMore && (
            <Button onClick={handleLoadMore} variant="contained">Load More</Button>
          )}
        </ButtonGroup>
      </Box>

    </Box>
  );
}
