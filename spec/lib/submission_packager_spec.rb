require 'spec_helper'
require 'tmpdir'
require 'shellwords'
require 'system_commands'

describe SubmissionPackager do
  include GitTestActions
  include SystemCommands
  
  before :each do
    @setup = SubmissionTestSetup.new(:exercise_name => 'SimpleExercise')
    @course = @setup.course
    @repo = @setup.repo
    @exercise_project = @setup.exercise_project
    @exercise = @setup.exercise
    @user = @setup.user
    @submission = @setup.submission
    
    @tar_path = Pathname.new('result.tar').expand_path.to_s
  end

  it "should package the submission in a tar file with tests from the repo" do
    @exercise_project.solve_all
    @exercise_project.make_zip(:src_only => false)
    
    SubmissionPackager.new.package_submission(@exercise, @exercise_project.zip_path, @tar_path)
    
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        `tar xf #{Shellwords.escape(@tar_path)}`
        File.should exist('src/SimpleStuff.java')
        File.read('src/SimpleStuff.java').should == File.read(@exercise_project.path + '/src/SimpleStuff.java')
        
        File.should exist('test/SimpleTest.java')
        File.should exist('test/SimpleHiddenTest.java')
      end
    end
  end

  it "can handle a zip with no parent directory over the src directory" do
    @exercise_project.solve_all
    Dir.chdir(@exercise_project.path) do
      system!("zip -q -0 -r #{@exercise_project.zip_path} src")
    end

    SubmissionPackager.new.package_submission(@exercise, @exercise_project.zip_path, @tar_path)

    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        `tar xf #{Shellwords.escape(@tar_path)}`
        File.should exist('src/SimpleStuff.java')
        File.read('src/SimpleStuff.java').should == File.read(@exercise_project.path + '/src/SimpleStuff.java')
      end
    end
  end
  
  it "should not use any tests from the submission" do
    @exercise_project.solve_all
    File.open(@exercise_project.path + '/test/SimpleTest.java', 'w') {|f| f.write('foo') }
    File.open(@exercise_project.path + '/test/NewTest.java', 'w') {|f| f.write('bar') }
    @exercise_project.make_zip(:src_only => false)
    
    SubmissionPackager.new.package_submission(@exercise, @exercise_project.zip_path, @tar_path)
    
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        `tar xf #{Shellwords.escape(@tar_path)}`
        File.read('test/SimpleTest.java').should == File.read(@exercise.clone_path + '/test/SimpleTest.java')
        File.should_not exist('test/NewTest.java')
      end
    end
  end

  it "should use tests from the submission if specified in .tmcproject.yml's extra_student_files" do
    File.open("#{@exercise.clone_path}/.tmcproject.yml", 'w') do |f|
      f.write("extra_student_files:\n  - test/SimpleTest.java\n  - test/NewTest.java")
    end

    @exercise_project.solve_all
    File.open(@exercise_project.path + '/test/SimpleTest.java', 'w') {|f| f.write('foo') }
    File.open(@exercise_project.path + '/test/NewTest.java', 'w') {|f| f.write('bar') }
    @exercise_project.make_zip(:src_only => false)

    SubmissionPackager.new.package_submission(@exercise, @exercise_project.zip_path, @tar_path)

    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        `tar xf #{Shellwords.escape(@tar_path)}`
        File.read('test/SimpleTest.java').should == 'foo'
        File.read('test/NewTest.java').should == 'bar'
      end
    end
  end

  it "should not use .tmcproject.yml from the submission" do
    @exercise_project.solve_all
    File.open("#{@exercise_project.path}/.tmcproject.yml", 'w') do |f|
      f.write("extra_student_files:\n  - test/SimpleTest.java\n  - test/NewTest.java")
    end
    File.open(@exercise_project.path + '/test/SimpleTest.java', 'w') {|f| f.write('foo') }
    File.open(@exercise_project.path + '/test/NewTest.java', 'w') {|f| f.write('bar') }
    @exercise_project.make_zip(:src_only => false)

    SubmissionPackager.new.package_submission(@exercise, @exercise_project.zip_path, @tar_path)

    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        `tar xf #{Shellwords.escape(@tar_path)}`
        File.read('test/SimpleTest.java').should == File.read(@exercise.clone_path + '/test/SimpleTest.java')
        File.should_not exist('test/NewTest.java')
        File.should_not exist('.tmcproject.yml')
      end
    end
  end

  it "should include the .tmcrc file if present" do
    File.open("#{@exercise.clone_path}/.tmcrc", 'w') do |f|
      f.write("hello")
    end

    @exercise_project.solve_all
    @exercise_project.make_zip(:src_only => false)

    SubmissionPackager.new.package_submission(@exercise, @exercise_project.zip_path, @tar_path)

    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        `tar xf #{Shellwords.escape(@tar_path)}`
        File.should exist('.tmcrc')
        File.read('.tmcrc').should == 'hello'
      end
    end
  end

  it "should not use .tmcrc from the submission" do
    @exercise_project.solve_all
    File.open("#{@exercise_project.path}/.tmcrc", 'w') do |f|
      f.write("hello")
    end
    @exercise_project.make_zip(:src_only => false)

    SubmissionPackager.new.package_submission(@exercise, @exercise_project.zip_path, @tar_path)

    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        `tar xf #{Shellwords.escape(@tar_path)}`
        File.should_not exist('.tmcrc')
      end
    end
  end

  it "should add tmc-junit-runner.jar and its deps to lib/testrunner/" do
    @exercise_project.solve_all
    @exercise_project.make_zip(:src_only => false)
    
    SubmissionPackager.new.package_submission(@exercise, @exercise_project.zip_path, @tar_path)
    
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        `tar xf #{Shellwords.escape(@tar_path)}`
        File.read('lib/testrunner/tmc-junit-runner.jar').should == File.read(TmcJunitRunner.jar_path)
        for original_path in TmcJunitRunner.jar_and_lib_paths
          File.read("lib/testrunner/#{original_path.basename}").should == File.read(original_path)
        end
      end
    end
  end
  
  describe "tmc-run script added to the archive" do
    it "should compile and run the submission" do
      @exercise_project.solve_all
      @exercise_project.make_zip(:src_only => false)
      
      SubmissionPackager.new.package_submission(@exercise, @exercise_project.zip_path, @tar_path)
      
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          sh! ['tar', 'xf', @tar_path]
          File.should_not exist('classes/main/SimpleStuff.class')
          File.should_not exist('output.txt')
          
          begin
            sh! ["env", "JAVA_RAM_KB=#{64*1024}", "./tmc-run"]
          rescue
            if File.exist?('output.txt')
              raise($!.message + "\n" + "The contents of output.txt:\n" + File.read('output.txt'))
            else
              raise
            end
          end
          
          File.should exist('classes/main/SimpleStuff.class')
          File.should exist('output.txt')
        end
      end
    end
    
    it "should report compilation errors in output.txt with exit code 101" do
      @exercise_project.introduce_compilation_error
      @exercise_project.make_zip(:src_only => false)
      
      SubmissionPackager.new.package_submission(@exercise, @exercise_project.zip_path, @tar_path)
      
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          sh! ['tar', 'xf', @tar_path]
          File.should_not exist('classes/main/SimpleStuff.class')
          File.should_not exist('output.txt')
          `env JAVA_RAM_KB=#{64*1024} ./tmc-run`
          $?.exitstatus.should == 101
          File.should exist('output.txt')
          
          output = File.read('output.txt')
          output.should include('compiler should fail here')
        end
      end
    end

    it "should source .tmcrc" do
      File.open("#{@exercise.clone_path}/.tmcrc", 'w') do |f|
        f.write("echo $TESTS > lol.txt")
      end

      @exercise_project.solve_all
      @exercise_project.make_zip(:src_only => false)

      SubmissionPackager.new.package_submission(@exercise, @exercise_project.zip_path, @tar_path)

      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          sh! ['tar', 'xf', @tar_path]

          begin
            sh! ["env", "JAVA_RAM_KB=#{64*1024}", "./tmc-run"]
          rescue
            if File.exist?('output.txt')
              raise($!.message + "\n" + "The contents of output.txt:\n" + File.read('output.txt'))
            else
              raise
            end
          end

          File.should exist('lol.txt')
          File.read('lol.txt').should include('SimpleTest.testAdd')
        end
      end
    end
  end
end
