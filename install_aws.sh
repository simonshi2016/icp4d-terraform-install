#!/bin/bash
cd /tmp
wget https://bootstrap.pypa.io/get-pip.py
python3 get-pip.py 
pip3 install awscli --upgrade
