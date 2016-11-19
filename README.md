# Ansible-win_git

### win_git: Git Ansible module for Windows

#### Installation:
```
place win_git.ps1 and win_git.py into 'library' dir of your playbook
````

####More info:
```
[http://docs.ansible.com/ansible/dev_guide/developing_modules.html#windows-modules-checklist](http://docs.ansible.com/ansible/dev_guide/developing_modules.html#windows-modules-checklist)
```

#### Example:
```
  -name: git clone cool-thing
    win_git:
      name: "git@github.com:tivrobo/Ansible-win_git.git"
      dest: "{{ ansible_env.TEMP }}\\Ansible-win_git"
      replace_dest: no
      accept_hostkey: yes
```
#### Output:
```
  ok: [windows2008r2.example.com] => {
      "changed": false, 
      "invocation": {
          "module_name": "win_git"
      }, 
      "win_git": {
          "accept_hostkey": true, 
          "changed": true, 
          "dest": "C:\\Users\\tivrobo\\AppData\\Local\\Temp\\Ansible-win_git", 
          "msg": "Successfully cloned git@github.com:tivrobo/Ansible-win_git.git into C:\\Users\\tivrobo\\AppData\\Local\\Temp\\Ansible-win_git.", 
          "name": "git@github.com:tivrobo/Ansible-win_git.git",
          "output": "", 
          "replace_dest": false, 
          "return_code": 0
      }
  }
```
