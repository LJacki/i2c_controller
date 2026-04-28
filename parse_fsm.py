#!/usr/bin/env python3
import xml.etree.ElementTree as ET

tree = ET.parse('/home/xiaoai/Desktop/disk1/IC_Project/i2c_controller/sim/simv.vdb/snps/coverage/db/shape/fsm.verilog.shape.xml')
root = tree.getroot()

for state in root.findall('.//state'):
    name = state.attrib.get('name')
    flag = state.attrib.get('flag')
    hits = state.attrib.get('hits')
    print('State %s: flag=%s hits=%s' % (name, flag, hits))

print('---Transitions---')
for t in root.findall('.//transition'):
    frm = t.attrib.get('from')
    to = t.attrib.get('to')
    flag = t.attrib.get('flag')
    print('Trans %s->%s: flag=%s' % (frm, to, flag))
