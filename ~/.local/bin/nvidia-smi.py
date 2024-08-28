#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# SPDX-License-Identifier: AGPL-3.0-or-later

import argparse
import json
import subprocess
import sys
from xml.etree import ElementTree

available_metrics = (
    'power.draw',                 # Power usage in watts
    'temperature.gpu',            # Temperature in degrees Celsius (℃)
    'clocks.graphics',            # Graphics clock
    'memory.framebuffer.used',    # Framebuffer memory usage
)

parser = argparse.ArgumentParser(description='NVIDIA System Management Interface metrics on i3bar.')

parser.add_argument('-i', '--index', metavar='IDX', type=int, default=0,
                                     help='i3bar position of the GPU metrics (default: %(default)s)')
parser.add_argument('-m', '--metrics', metavar='KEYS', nargs='+',
                          choices=available_metrics, default=available_metrics,
                          help='metrics to show on i3bar (default: %(default)s)')
parser.add_argument('-g', '--gpu', metavar='ID', type=int, default=0,
                                   help='which GPU to monitor (default: %(default)s)')
parser.add_argument('-F', metavar='FMT', default='{value} {unit}', dest='full_text_format',
                          help='descriptive text format (default: "%(default)s")')
parser.add_argument('-f', metavar='FMT', default='{value}', dest='short_text_format',
                          help='used when out of screen space (default "%(default)s")')
parser.add_argument('--nvidia-smi', metavar='PATH', default='nvidia-smi',
                                    help='path to the nvidia-smi binary')

parameters = parser.parse_args()

gpu_id = parameters.gpu
nvidia_smi = parameters.nvidia_smi
index = parameters.index
selected_metrics = parameters.metrics

nvidia_smi_command = [nvidia_smi, '--query', '--xml-format']
templates = {
    'full': parameters.full_text_format,
    'short': parameters.short_text_format
}

def dig(d, *keys):
    for k in keys:
        d = d[k]

    return d

thresholds = {
    'temperature.gpu': ['temperature', 'maximum']
}

def is_above_threshold(key, value, metrics):
    if key in thresholds:
        threshold = dig(metrics, *[*thresholds[key], 'value'])
        return value > threshold

largest_values = {
    'power.draw': '99.99 W',
    'temperature.gpu': ['temperature', 'shutdown'],
    'clocks.graphics': ['clocks', 'maximum', 'graphics'],
    'memory.framebuffer.used': ['memory', 'framebuffer', 'total'],
}

def min_width_for(key, metrics):
    if key in largest_values:
        largest = largest_values[key]

        if type(largest) == list:
            largest = str.format(templates['full'], key=key, **dig(metrics, *largest))

        return str(largest)

def query_nvidia_gpu():
    completed = subprocess.run(nvidia_smi_command, capture_output=True, text=True)
    return ElementTree.fromstring(completed.stdout)

def parse(xml):
    def parse_value(s):
        if s.text == 'N/A':
            return None

        value, unit = s.text.split()
        type = int

        if unit == 'C':
            unit = '℃'
        if unit == 'W':
            type = float

        return { 'value': type(value), 'unit': unit }

    def parse_state(s):
        if s.text == 'Active':
            return True
        elif s.text == 'Not Active':
            return False
        else:
            return None

    def parse_throttling_reasons(t):
        return {
            'idle': parse_state(t.find('clocks_throttle_reason_gpu_idle')),

            'sw_power_cap': parse_state(t.find('clocks_throttle_reason_sw_power_cap')),
            'sw_thermal_slowdown': parse_state(t.find('clocks_throttle_reason_sw_thermal_slowdown')),

            'hw_slowdown': parse_state(t.find('clocks_throttle_reason_hw_slowdown')),
            'hw_thermal_slowdown': parse_state(t.find('clocks_throttle_reason_hw_thermal_slowdown')),
            'hw_power_brake_slowdown': parse_state(t.find('clocks_throttle_reason_hw_power_brake_slowdown')),

            'display_clocks_setting': parse_state(t.find('clocks_throttle_reason_display_clocks_setting')),
            'applications_clocks_setting': parse_state(t.find('clocks_throttle_reason_applications_clocks_setting')),

            'sync_boost': parse_state(t.find('clocks_throttle_reason_sync_boost'))
        }

    def parse_memory(m):
        return {
            'total': parse_value(m.find('total')),
            'used': parse_value(m.find('used')),
            'free': parse_value(m.find('free')),
        }

    def parse_utilization(u):
        return {
            'gpu': parse_value(u.find('gpu_util')),
            'memory': parse_value(u.find('memory_util')),
            'encoder': parse_value(u.find('encoder_util')),
            'decoder': parse_value(u.find('decoder_util')),
        }

    def parse_temperature(t):
        return {
            'gpu': parse_value(t.find('gpu_temp')),
            'shutdown': parse_value(t.find('gpu_temp_max_threshold')),
            'slowdown': parse_value(t.find('gpu_temp_slow_threshold')),
            'maximum': parse_value(t.find('gpu_temp_max_gpu_threshold')),
        }

    def parse_power(p):
        return {
            'state': p.find('power_state').text,
            'draw': parse_value(p.find('power_draw'))
        }

    def parse_clocks(c, cmax):
        return {
            'graphics': parse_value(c.find('graphics_clock')),
            'sm': parse_value(c.find('sm_clock')),
            'memory': parse_value(c.find('mem_clock')),
            'video': parse_value(c.find('video_clock')),

            'maximum': {
                'graphics': parse_value(cmax.find('graphics_clock')),
                'sm': parse_value(cmax.find('sm_clock')),
                'memory': parse_value(cmax.find('mem_clock')),
                'video': parse_value(cmax.find('video_clock')),
            }
        }

    gpu_count = xml.find('attached_gpus')
    gpu = xml.findall('gpu')[gpu_id]

    return {
        'fan': parse_value(gpu.find('fan_speed')),
        'throttling': parse_throttling_reasons(gpu.find('clocks_throttle_reasons')),
        'memory': {
            'framebuffer': parse_memory(gpu.find('fb_memory_usage')),
            'bar1': parse_memory(gpu.find('bar1_memory_usage'))
        },
        'utilization': parse_utilization(gpu.find('utilization')),
        'temperature': parse_temperature(gpu.find('temperature')),
        'power': parse_power(gpu.find('power_readings')),
        'clocks': parse_clocks(gpu.find('clocks'), gpu.find('max_clocks'))
    }

def create_instance(key, data, **keywords):
    def format_text(template):
        return str.format(template, key=key, **data)

    instance = {
        'name': 'nvidia-smi.py',
        'instance': key,
        'full_text': format_text(templates['full']),
        'short_text': format_text(templates['short']),
        'separator': False,
        'separator_block_width': 8
    }

    for keyword, value in keywords.items():
        if value is not None:
            instance[keyword] = value

    return instance

def add_nvidia_metrics(json_array):
    metrics = parse(query_nvidia_gpu())
    chosen = {selected: dig(metrics, *selected.split('.')) for selected in selected_metrics}
    instances = [create_instance(key, data,
                                 urgent=is_above_threshold(key, data['value'], metrics),
                                 min_width=min_width_for(key, metrics))
                 for key, data in chosen.items()]

    # Last block should have a separator
    last = instances[-1]
    last.pop('separator')
    last.pop('separator_block_width')

    json_array[index:index] = instances

z = False
if z:
    x = []
    add_nvidia_metrics(x)
    for y in x:
        print(y)
    sys.exit()

# i3bar protocol handling
# https://i3wm.org/docs/i3bar-protocol.html

def write(*lines):
    for line in lines:
        sys.stdout.write(line + '\n')
        sys.stdout.flush()

def read():
    try:
        line = sys.stdin.readline().strip()

        # i3status sent EOF or an empty line
        if not line:
            sys.exit(3)

        return line

    except KeyboardInterrupt:
        sys.exit()

def ignore_leading_comma(line):
    prefix = ''

    if line.startswith(','):
        line, prefix = line[1:], ','

    return line, prefix

def process(line, f):
    line, prefix = ignore_leading_comma(line)
    data = json.loads(line)

    f(data)

    write(prefix + json.dumps(data))

if __name__ == '__main__':
    # First line contains the version header.
    # Second line contains the start of the infinite array.
    write(read(), read())

    while True:
        process(read(), add_nvidia_metrics)
