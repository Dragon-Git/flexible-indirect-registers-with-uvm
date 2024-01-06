/**
 #----------------------------------------------------------------------
 #   Copyright 2007-2017 Cadence Design Systems, Inc.
 #   All Rights Reserved Worldwide
 #
 #   Licensed under the Apache License, Version 2.0 (the
 #   "License"); you may not use this file except in
 #   compliance with the License.  You may obtain a copy of
 #   the License at
 #
 #       http://www.apache.org/licenses/LICENSE-2.0
 #
 #   Unless required by applicable law or agreed to in
 #   writing, software distributed under the License is
 #   distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 #   CONDITIONS OF ANY KIND, either express or implied.  See
 #   the License for the specific language governing
 #   permissions and limitations under the License.
 #----------------------------------------------------------------------
 */


// small testcase to illustrate the indirect register approach
module test444;
	import  uvm_pkg::*;
	import cdns_generic_indirect_register::*;
	import tb_pkg::*;

	// our example dut
	dut mydut();

	// an example sequencer with an embedded driver which simply invokes read/write 
	// directly in the dut
	class uvm_nodriver_sequencer#(type A=trans_t,type B=A) extends uvm_push_sequencer#(A,B);
		class dummy_push_driver extends uvm_push_driver#(A,B);
			`uvm_component_utils(dummy_push_driver)
			function new (string name = "dummy_push_driver", uvm_component parent = null);
				super.new(name, parent);
			endfunction
			virtual task put(A item);

				// shortcut interface to HW
				if(item.orig.kind==UVM_READ)
					item.orig.data=mydut.read(item.orig.addr);
				else
					mydut.write(item.orig.addr,item.orig.data);

				`uvm_info("DRV",$sformatf("got a %s %p",item.get_type_name(),item),UVM_MEDIUM)
			endtask
		endclass

		local dummy_push_driver _driver= new("dummy_push_driver",this);
		`uvm_sequencer_param_utils(uvm_nodriver_sequencer#(A,B))

		virtual function void connect_phase(uvm_phase phase);
			super.connect_phase(phase);
			req_port.connect(_driver.req_export);
		endfunction

		function new (string name = "uvm_nodriver_sequencer", uvm_component parent = null);
			super.new(name, parent);
		endfunction
	endclass

	// a simple/example test with
	// 10 unmapped uvm_reg instances accessible via selection in the index register field
	// 1 register holding a uvm_reg_field with the index
	// each of the 10 uvm_reg instances have a frontdoor attached so that one can read/write 
	// to them which the frontdoor translates into access to the index field plus the data reg
	class test extends uvm_test;
		function new (string name = "test", uvm_component parent = null);
			super.new(name, parent);
		endfunction

		`uvm_component_utils(test)

		GenericIndirectRegister#(uvm_reg,int unsigned) idatareg ;
		URFindexProvider ip;
		MyIndexableStorageI sp;
		block_B regblk;

		reg_R indexreg;
		reg_R registerset[10];

		virtual function void build_phase(uvm_phase phase);
			super.build_phase(phase);

			regblk=new("regblk");
			regblk.default_map = regblk.create_map("regmap",0,4,UVM_BIG_ENDIAN);
			regblk.default_map.set_auto_predict(1);

			// the reg field holding the index
			indexreg = new("indexreg");
			indexreg.build();
			indexreg.configure(regblk, null);

			// build and configure  "indirect" register
			idatareg = new("idatareg",32,UVM_NO_COVERAGE);
			idatareg.configure(regblk,null);

			ip=new();                           // allocate index provider
			sp=new();                           // allocate storage provider

			foreach(registerset[idx]) begin
				registerset[idx] = new($sformatf("areg[%0d]",idx)); // actual registers we are indexing
				registerset[idx].build();
				registerset[idx].configure(regblk, null, $sformatf("rgareg[%0d]",idx));
				regblk.default_map.add_reg(registerset[idx],0+4*idx+8,"RW",1);
			end

			regblk.default_map.add_reg(idatareg,0,"RW"); // index reg @ addr=0
			regblk.default_map.add_reg(indexreg,4,"RW"); // data register reg @ addr=4

			void'(ip.set(indexreg._dummy)); // configure index provider with actual register field
			void'(sp.set(registerset));     // configure storage with actual storage array

			void'(idatareg.setIndexProvider(ip).setStorage(sp));  // configure indirect register properly

			// "seal" the register model
			regblk.lock_model();

			// (optional)
			// add frontdoor to registers in order to translate direct access to register into
			// indirect access
			foreach(registerset[idx]) begin
					IregFrontdoor#(uvm_reg,int unsigned) fd = new($sformatf("ftdr-%0d",idx));
					fd.configure(idatareg,ip,sp,registerset[idx]);
					registerset[idx].set_frontdoor(fd);
			end
			
			begin
				// setup UVM register adapter and sequencer for the map holding our registers
				uvm_nodriver_sequencer seqr = new("seqr",null);
				bus2reg_adapter a = new("adapter");
				regblk.default_map.set_sequencer(seqr,a);
			end
		endfunction


		virtual task run_phase(uvm_phase phase);
			uvm_status_e status;
			uvm_reg_data_t data;

			super.run_phase(phase);

			// block until we are done
			phase.raise_objection(this);

			indexreg._dummy.write(status,3);  // select index
			idatareg.write(status,15); // write actually to index rg[3]

			indexreg._dummy.write(status,2);  // select index
			idatareg.read(status,data);
			`uvm_info("TEST",$sformatf("got %0x",data),UVM_NONE)

			indexreg._dummy.write(status,3);  // select index
			idatareg.read(status,data);
			`uvm_info("TEST",$sformatf("got %0x",data),UVM_NONE)

			registerset[5].write(status,14);
			registerset[3].read(status,data);

			// now at least we are done
			phase.drop_objection(this);
		endtask
	endclass
	
	// the obvious run_test
	initial run_test();
endmodule
