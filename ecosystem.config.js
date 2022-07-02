module.exports = {
  apps: [
    {
      name: 'maker',
      script: 'npx',
      args: 'hardhat run --network mainnet scripts/maker.ts',
      autorestart: true,
      max_restarts: 5,
      min_uptime: '10s',
      restart_delay: 5000,
      out_file: 'logs/maker/normal.log',
      error_file: 'logs/maker/error.log',
      combine_logs: true,
    },
  ]
};