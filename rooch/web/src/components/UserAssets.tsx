'use client';
import { useEffect, useMemo, useRef, useState } from 'react'
import Typography from '@mui/material/Typography';
import Box from '@mui/material/Box';
import { Card, CardContent, Grid } from '@mui/material';
import Pagination from '@mui/material/Pagination';
import Snackbar from '@mui/material/Snackbar';
import Alert from '@mui/material/Alert';
import CircularProgress from '@mui/material/CircularProgress';

import { Movescription } from '@/types'
import { movescriptionConfig } from '@/config/movescription'
import { GlobalStateFilterView } from '@roochnetwork/rooch-sdk'
import { useRoochClientQuery } from '@roochnetwork/rooch-sdk-kit'

const itemsPerPage = 20;

export type UserAssetsProps = {
  address: string,
}

export default function UserAssets(props: UserAssetsProps) {
  const [page, setPage] = useState<number>(1);
  const [items, setItems] = useState<Array<Movescription>>([]);
  const handleChange = (event: any, value: number) => {
    setPage(value);
  };

  const [filter, setFilter] = useState<GlobalStateFilterView>({
    object_type_with_owner: {
      object_type: `${movescriptionConfig.movescriptionAddress}::movescription::Movescription`,
      owner: props.address,
    }
  });
  const [paginationModel, setPaginationModel] = useState({ page: 0, pageSize: 10 })
  const mapPageToNextCursor = useRef<{ [page: number]: string | null }>({})

  const queryOptions = useMemo(
    () => ({
      cursor: mapPageToNextCursor.current[paginationModel.page - 1],
      pageSize: paginationModel.pageSize,
    }),
    [paginationModel],
  )

  let { data, isPending, error } = useRoochClientQuery(
    'queryGlobalStates',
    {
      filter: filter,
      cursor: queryOptions.cursor,
      limit: paginationModel.pageSize,
    },
    {
      enabled: true,
    },
  )

  useEffect(() => {
    if (!data) {
      return
    }

    let items = new Array<Movescription>();

    for (const state of data.data) {
      items.push({
        object_id: `${state.object_id}`,
        tick: "MOVE",
        value: 925,
      })
    }

    setItems(items);
  }, [])

  return (
    <Box sx={{ maxWidth: 'lg' }}>
      <Snackbar open={error != null} autoHideDuration={6000}>
        <Alert severity="error">
          {error?.message}
        </Alert>
      </Snackbar>
      {isPending ? (
        <CircularProgress></CircularProgress>
      ) : (
        <Grid container spacing={2}>
          {items.slice((page - 1) * itemsPerPage, page * itemsPerPage).map((item) => (
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
          ))}
        </Grid>
      )}
      <Pagination count={Math.ceil(items.length / itemsPerPage)} page={page} onChange={handleChange} />
    </Box>
  );
}
