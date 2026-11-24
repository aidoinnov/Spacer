#!/usr/bin/env python3
"""Pool one declared precision supplement, retaining and identifying all attempts."""
import argparse,copy,json
from pathlib import Path

def merge(base,supplement):
 if any(raw.get("warmup_pairs",0) or raw.get("warmup_rows") for raw in (base,supplement)):
  raise ValueError("warmup collections require separate reporting; pooling is unsupported")
 for key in ('variants','planned_scenarios','fixture_storage','fixture_setup_sync','scope'):
  if base.get(key)!=supplement.get(key):raise ValueError('changed collection identity: '+key)
 for raw in (base,supplement):
  if raw['status']!='measured' or raw.get('cleanup',{}).get('removed') is not True:raise ValueError('incomplete collection')
  expected=raw['pairs']*len(raw['planned_scenarios'])*len(raw['variants'])
  if len(raw['rows'])!=expected:raise ValueError('missing attempts')
  cells={(row['scenario'],row['variant'],row['pair']) for row in raw['rows']}
  if len(cells)!=expected:raise ValueError('duplicate attempts')
  if any(row['pair'] not in range(raw['pairs']) for row in raw['rows']):raise ValueError('pair out of range')
 for scenario in base['planned_scenarios']:
  if base['summary'][scenario]['expected']!=supplement['summary'][scenario]['expected']:raise ValueError('changed fixture oracle')
 merged=copy.deepcopy(base)
 merged['pairs']=base['pairs']+supplement['pairs'];merged['summary']={k:{'expected':v['expected']} for k,v in base['summary'].items()}
 merged['rows']=[]
 for collection,raw,offset in [('initial',base,0),('fixed_supplement',supplement,base['pairs'])]:
  for original in raw['rows']:
   row=copy.deepcopy(original);row.update(source_collection=collection,source_pair=row['pair'],pair=row['pair']+offset);merged['rows'].append(row)
 merged['collections']=[{'name':name,'pairs':raw['pairs'],'started':raw['started'],'cleanup':raw['cleanup']} for name,raw in [('initial',base),('fixed_supplement',supplement)]]
 merged['cleanup']={'removed':True,'note':'all source collections individually removed owned fixtures'}
 return merged

def main():
 p=argparse.ArgumentParser();p.add_argument('--base',type=Path,required=True);p.add_argument('--supplement',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 if a.output.exists():raise SystemExit('refusing overwrite')
 r=merge(json.loads(a.base.read_text()),json.loads(a.supplement.read_text()))
 r['source_files']=[str(a.base),str(a.supplement)];a.output.write_text(json.dumps(r,indent=2)+'\n')
if __name__=='__main__':main()
