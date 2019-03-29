#!/bin/bash
param=$@
docker run -it -v $(pwd):/icp4d_installer --network=host tf_installer $param
