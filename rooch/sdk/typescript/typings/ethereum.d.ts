declare global {
  interface Window {
    ethereum: Ethereum;
  }
}

interface Ethereum {
  request(request: EthereumRequest): Promise<void>;
}

interface EthereumRequest {
  method: string;
  params: Params;
}

type TransactionParam = {
  from: string;
  to: string;
  value: string;
};

type Params = TransactionParam[];
