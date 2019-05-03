# ansible-win_git
Git module for Windows
## Installation:
Copy ***win_git.ps1*** and ***win_git.py*** files to **[default-module-path](http://docs.ansible.com/ansible/latest/reference_appendices/config.html#default-module-path)** directory
## Usage:
```
- name: git clone cool-thing
  win_git:
    repo: "git@github.com:tivrobo/Ansible-win_git.git"
    dest: "{{ ansible_env.TEMP }}\\Ansible-win_git"
    branch: master
    update: no
    recursive: yes
    replace_dest: no
    accept_hostkey: yes
```
## Output:
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
    "repo": "git@github.com:tivrobo/Ansible-win_git.git",
    "output": "", 
    "recursive": true, 
    "replace_dest": false, 
    "return_code": 0
  }
}
```
## TODO:
- [ ] handle correct status change when using update
- [ ] add check/diff mode support
- [ ] check for idempotence
- [ ] add tests
## More info:
- http://docs.ansible.com/ansible/latest/dev_guide/developing_modules_general_windows.html
