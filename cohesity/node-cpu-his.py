#!/usr/bin/env python
"""get cluster vips by least busy CPU"""

# import pyhesity wrapper module
from pyhesity import *

# command line arguments
import argparse
parser = argparse.ArgumentParser()
parser.add_argument('-v', '--vip', type=str, required=True)         # cluster to connect to
parser.add_argument('-u', '--username', type=str, required=True)    # username
parser.add_argument('-d', '--domain', type=str, default='local')    # (optional) domain - defaults to local
parser.add_argument('-i', '--useApiKey', action='store_true')       # use API key authentication
parser.add_argument('-pwd', '--password', type=str, default=None)   # optional password

args = parser.parse_args()

vip = args.vip
username = args.username
domain = args.domain
password = args.password
useApiKey = args.useApiKey

# authenticate
apiauth(vip=vip, username=username, domain=domain, password=password, useApiKey=useApiKey, noretry=True, quiet=True)

nowMsecs = int(timeAgo(1, 'seconds') / 1000)
hourAgoMsecs = int(timeAgo(1, 'hours') / 1000)
dayAgoMsecs = int(timeAgo(1, 'days') / 1000)
weekAgoMsecs = int(timeAgo(1, 'weeks') / 1000)

nodes = api('get', 'nodes')

#print(nodes['id'] + ',')
nodes_all = 'Date-time'
for node in nodes:
    nodes_all = nodes_all + ',' + str(node['id'])
print(nodes_all)
i = 1
for node in nodes:
#    print(node['id'])
    print(i)
#    cpustats = api('get', 'statistics/timeSeriesStats?endTimeMsecs=%s&entityId=%s&metricName=kCpuUsagePct&metricUnitType=9&range=day&rollupFunction=average&rollupIntervalSecs=360&schemaName=kSentryNodeStats&startTimeMsecs=%s' % (nowMsecs, node['id'], hourAgoMsecs))
#    cpustats = api('get', 'statistics/timeSeriesStats?endTimeMsecs=%s&entityId=%s&metricName=kCpuUsagePct&metricUnitType=9&range=day&rollupFunction=average&rollupIntervalSecs=360&schemaName=kSentryNodeStats&startTimeMsecs=%s' % (nowMsecs, node['id'], dayAgoMsecs))
    cpustats = api('get', 'statistics/timeSeriesStats?endTimeMsecs=%s&entityId=%s&metricName=kCpuUsagePct&metricUnitType=9&range=day&rollupFunction=average&rollupIntervalSecs=360&schemaName=kSentryNodeStats&startTimeMsecs=%s' % (nowMsecs, node['id'], weekAgoMsecs))
    for dataPoint in cpustats['dataPointVec']:
        print('\t%s\t%s' % (usecsToDate(dataPoint['timestampMsecs'] * 1000), round(dataPoint['data']['doubleValue'], 1)))
    i += 1
print(i)
