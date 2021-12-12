jq -rS '.return[].unmount' snapshot.json | jq -r '.[]' | sudo sh
sudo zfs destroy -r pool@backup:dataset
rm snapshot.json 
